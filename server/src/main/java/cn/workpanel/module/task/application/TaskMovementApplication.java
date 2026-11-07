package cn.workpanel.module.task.application;

import cn.workpanel.*;
import cn.workpanel.module.task.*;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 日期平移用例；同键锁 → 最新身份/资源 → 重放 → 任务锁 → 候选与幂等记录同事务。 */
@Service
public class TaskMovementApplication {
    private final Db db;
    private final cn.workpanel.module.task.infrastructure.TaskMovementRepository commands;
    private final CurrentActors actors;
    private final ScheduleConstraints constraints;
    private final ReviewApplicationService reviews;
    private final TaskRevisionService revisions;
    public TaskMovementApplication(Db db,CurrentActors actors,ScheduleConstraints constraints,ReviewApplicationService reviews,TaskRevisionService revisions,cn.workpanel.module.task.infrastructure.TaskMovementRepository commands) {
        this.commands=commands;
        this.db=db;this.actors=actors;this.constraints=constraints;this.reviews=reviews;this.revisions=revisions;
    }
    @Transactional
    public Map<String,Object> request(Actor identity,String id,Map<String,Object> body,String key,String constraintRevision) {
        if(!body.containsKey("moveDays")) {
            Actor a=actors.fresh(identity);
            var request=revisions.prepareReschedule(a,id,body);
            return reviews.create(a,"TASK_RESCHEDULE",id,request.version(),request.before(),request.candidate(),Db.required(body,"reason"));
        }
        if(!body.keySet().equals(Set.of("version","moveDays","reason"))) throw ApiError.bad("INVALID_RESCHEDULE_MODE","移动模式只接受 version、moveDays、reason");
        int version=TaskSchedule.integer(body.get("version"),true,"INVALID_VERSION");
        int days=TaskSchedule.integer(body.get("moveDays"),false,"INVALID_MOVE_DAYS");
        String reason=TaskSchedule.reason(body.get("reason")); TaskSchedule.key(key);
        if(constraintRevision==null || !constraintRevision.matches("calendar-v[0-9]+-[0-9]{4}")) throw ApiError.bad("INVALID_SCHEDULE_CONSTRAINTS","需要有效排期约束版本");
        commands.lockKey(identity,key);
        Actor a=actors.fresh(identity); a.requireDispatch();
        var task=TaskAccess.readable(db,a,id,false);
        if(!a.admin()&&!a.id().equals(Db.str(task,"issuer_id"))) throw ApiError.forbidden();
        var old=commands.find(a,key);
        if(!old.isEmpty()) {
            var record=old.getFirst();
            if(((Number)record.get("hash_version")).intValue()!=1) throw new IllegalStateException("Unsupported task move hash version");
            if(!hashV1(id,version,days,reason,constraintRevision).equals(Db.str(record,"request_hash"))) throw new ApiError(409,"IDEMPOTENCY_CONFLICT","同一幂等键内容不同");
            return reviews.get(a,Db.str(record,"review_id"));
        }
        task=TaskAccess.readable(db,a,id,true);
        // 行锁等待后重新验证身份，不持有用户行锁，避免与审核锁序构成环路。
        a=actors.fresh(identity); a.requireDispatch();
        task=TaskAccess.readable(db,a,id,false);
        if(!a.admin()&&!a.id().equals(Db.str(task,"issuer_id"))) throw ApiError.forbidden();
        if(!constraints.enabled()) throw new ApiError(409,"CALENDAR_MOVE_DISABLED","日历移动暂未开放");
        constraints.match(constraintRevision);
        if(((Number)task.get("version")).intValue()!=version) throw ApiError.conflict();
        if(Set.of("ARCHIVED","WITHDRAWN").contains(Db.str(task,"phase"))) throw new ApiError(409,"INVALID_TRANSITION","当前状态不允许移动");
        TaskSchedule.nextVersion(version);
        // 不锁既有审核行；批准端锁序为 review → task。
        if(commands.pending(a,id,version))
            throw new ApiError(409,"RESCHEDULE_PENDING","当前版本已有待审移动，请先查看申请");
        String start=TaskSchedule.instant(task.get("start_at")),end=TaskSchedule.instant(task.get("deadline"));
        var moved=TaskSchedule.move(start,end,days); constraints.validate(moved.startAt(),moved.deadline());
        var before=new LinkedHashMap<String,Object>();before.put("startAt",start);before.put("deadline",end);
        var candidate=new LinkedHashMap<String,Object>();candidate.put("scheduleMode","MOVE");candidate.put("moveDays",days);candidate.put("startAt",moved.startAt());candidate.put("deadline",moved.deadline());candidate.put("scheduleConstraints",constraints.view());
        var review=reviews.create(a,"TASK_RESCHEDULE",id,version,before,candidate,reason);
        commands.save(a,key,id,Db.str(review,"id"),hashV1(id,version,days,reason,constraintRevision));
        return review;
    }
    /** 算法 v1 必须保留供跨部署重放；JSON 数组避免分隔符碰撞。 */
    String hashV1(String id,int version,int days,String reason,String revision) { return Db.hash(db.write(List.of(id,version,days,reason,revision))); }
}
