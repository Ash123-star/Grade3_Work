package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 任务派发：校验 → 幂等锁 → 重放/冲突/新建，所有写入在同一事务内。 */
@Service
public class TaskDispatchService {
    final Db db; final ReviewApplicationService reviews;
    public TaskDispatchService(Db db,ReviewApplicationService reviews) { this.db=db; this.reviews=reviews; }
    /** 仅供历史 Mockito 单元测试构造；生产 Bean 必须注入审核服务。 */
    @Deprecated public TaskDispatchService(Db db) { this(db,null); }

    @Transactional
    public Map<String,Object> dispatch(Actor a,Map<String,Object> raw,String key) {
        a.requireDispatch();
        if(key==null||key.isBlank()||key.length()>128) throw ApiError.bad("IDEMPOTENCY_REQUIRED","需要 1–128 位幂等键");
        TaskDraft d=TaskDraftNormalizer.normalize(raw);
        TaskParticipants.validate(db,a,d); TaskLabels.validate(db,a,d); TaskAttachments.verify(db,a,null,d.attachments());
        // 事务级锁把同一派发人同一键的并发请求串行化。
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))",a.id()+":"+key);
        var old=db.rows("SELECT * FROM idempotency_keys WHERE actor_id=? AND key=?",a.id(),key);
        if(!old.isEmpty()) {
            var record=old.getFirst(); int version=((Number)record.get("hash_version")).intValue();
            String expected=version==1?TaskDraftNormalizer.legacyHash(db,raw):TaskDraftNormalizer.hash(db,d);
            if(!expected.equals(Db.str(record,"request_hash"))) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","同一幂等键内容不同");
            String reviewId=Db.str(record,"review_id");
            if(!reviewId.isBlank()&&reviews!=null) return reviews.get(a,reviewId);
            return detail(TaskAccess.issued(db,a,Db.str(record,"task_id")));
        }
        String id=Db.id(); var body=d.body();
        if(reviews==null) return legacyDispatch(a,key,id,d,body);
        var request=reviews.create(a,"TASK_CREATE",id,0,Map.of(),body,"创建任务");
        db.update("INSERT INTO idempotency_keys(company_id,actor_id,key,request_hash,task_id,hash_version,review_id) VALUES (?,?,?,?,?,2,?)",a.company(),a.id(),key,TaskDraftNormalizer.hash(db,d),id,Db.str(request,"id"));
        return request;
    }

    private Map<String,Object> legacyDispatch(Actor a,String key,String id,TaskDraft d,Map<String,Object> body) {
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version) VALUES (?,?,?,?,?,?::timestamptz,?::timestamptz,?::jsonb,'DISPATCHED',1)",id,a.company(),d.ownerId(),a.id(),d.title(),d.startAt(),d.deadline(),db.write(body));
        TaskParticipants.assign(db,a,id,d); TaskLabels.replace(db,a,id,d); TaskAttachments.bind(db,a,id,d.attachments(),false);
        TaskTimeline.append(db,a,id,"DISPATCHED",body,null,"DISPATCHED",1);
        db.update("INSERT INTO idempotency_keys(company_id,actor_id,key,request_hash,task_id,hash_version) VALUES (?,?,?,?,?,2)",a.company(),a.id(),key,TaskDraftNormalizer.hash(db,d),id);
        db.audit(a,"TASK_DISPATCHED",id,Map.of(),body,"派发任务"); return detail(TaskAccess.issued(db,a,id));
    }

    public Map<String,Object> read(Actor a,String id) { return detail(TaskAccess.readable(db,a,id,false)); }

    Map<String,Object> detail(Map<String,Object> task) { return TaskView.of(db,task,TaskTimeline.list(db,Db.str(task,"id"))); }
}
