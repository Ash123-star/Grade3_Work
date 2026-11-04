package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 任务派发：校验 → 幂等锁 → 重放/冲突/新建，所有写入在同一事务内。 */
@Service
public class TaskDispatchService {
    final Db db; final ReviewApplicationService reviews; final ScheduleConstraints constraints;
    @Autowired
    public TaskDispatchService(Db db,ReviewApplicationService reviews,ScheduleConstraints constraints) { this.db=db;this.reviews=reviews;this.constraints=constraints; }
    public TaskDispatchService(Db db,ReviewApplicationService reviews) {this(db,reviews,new ScheduleConstraints(false));}
    /** 仅供历史 Mockito 单元测试构造；生产 Bean 必须注入审核服务。 */
    @Deprecated public TaskDispatchService(Db db) { this(db,null); }

    @Transactional
    public Map<String,Object> dispatch(Actor a,Map<String,Object> raw,String key) {
        return dispatch(a,raw,key,null);
    }

    @Transactional public Map<String,Object> dispatch(Actor a,Map<String,Object> raw,String key,String constraintRevision) {
        a.requireDispatch();
        if(key==null||key.isBlank()||key.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","需要 1–128 位幂等键");
        TaskDraft d=TaskDraftNormalizer.normalize(raw);
        // 事务级锁把同一派发人同一键的并发请求串行化。
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.id()+":"+key);
        var old=db.rows("SELECT * FROM idempotency_keys WHERE actor_id=? AND key=?",a.id(),key);
        if(!old.isEmpty()) {
            var record=old.getFirst(); int version=((Number)record.get("hash_version")).intValue();
            String stored=Db.str(record,"request_hash");
            boolean matches=version==1?TaskDraftNormalizer.legacyHash(db,raw).equals(stored):version==2&&TaskDraftNormalizer.matchesHash(db,d,stored);
            if(!matches) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","同一幂等键内容不同");
            String reviewId=Db.str(record,"review_id");
            if(!reviewId.isBlank()&&reviews!=null) return reviews.get(a,reviewId);
            return detail(TaskAccess.issued(db,a,Db.str(record,"task_id")));
        }
        if(constraintRevision!=null) { constraints.match(constraintRevision);constraints.validate(d.startAt(),d.deadline()); }
        TaskParticipants.validate(db,a,d); TaskLabels.validate(db,a,d); TaskAttachments.verify(db,a,null,d.attachments());
        String id=Db.id(); var body=d.body();
        if(reviews==null) return legacyDispatch(a,key,id,d,body);
        var request=reviews.create(a,"TASK_CREATE",id,0,Map.of(),body,"创建任务");
        db.update("INSERT INTO idempotency_keys(company_id,actor_id,key,request_hash,task_id,hash_version,review_id) VALUES (?,?,?,?,?,2,?)",a.company(),a.id(),key,TaskDraftNormalizer.hash(db,d),id,Db.str(request,"id"));
        return request;
    }

    private Map<String,Object> legacyDispatch(Actor a,String key,String id,TaskDraft d,Map<String,Object> body) {
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version) VALUES (?,?,?,?,?,?::timestamptz,?::timestamptz,?::jsonb,'DISPATCHED',1)",id,a.company(),d.ownerId(),a.id(),d.title(),d.startAt(),d.deadline(),db.write(body));
        TaskParticipants.assign(db,a,id,d); TaskLabels.replace(db,a,id,d); TaskAttachments.bind(db,a,id,d.attachments(),false);
        for(var item:d.acceptanceChecklist()) db.update("INSERT INTO task_acceptance_items(company_id,task_id,version,item_id,body) VALUES (?,?,1,?,?::jsonb)",a.company(),id,item.get("id"),db.write(item));
        TaskTimeline.append(db,a,id,"DISPATCHED",body,null,"DISPATCHED",1);
        db.update("INSERT INTO idempotency_keys(company_id,actor_id,key,request_hash,task_id,hash_version) VALUES (?,?,?,?,?,2)",a.company(),a.id(),key,TaskDraftNormalizer.hash(db,d),id);
        db.audit(a,"TASK_DISPATCHED",id,Map.of(),body,"派发任务"); return detail(TaskAccess.issued(db,a,id));
    }

    public Map<String,Object> read(Actor a,String id) {
        var task=TaskAccess.readable(db,a,id,false);var result=detail(task);
        var pin=db.rows("SELECT pinned_at FROM task_pins WHERE user_id=? AND task_id=?",a.id(),id);
        result.put("pinned",!pin.isEmpty()); result.put("pinnedAt",pin.isEmpty()?null:pin.getFirst().get("pinned_at"));
        result.put("capabilities",Map.of("reschedule",constraints.mayMove(a,task)));result.put("scheduleConstraints",constraints.view());return result;
    }

    Map<String,Object> detail(Map<String,Object> task) { return TaskView.of(db,task,TaskTimeline.list(db,Db.str(task,"id"))); }
}
