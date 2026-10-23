package cn.workpanel.module.task.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.task.*;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** AI 等跨模块调用的实际任务应用适配，始终复用普通任务校验并加入调用方事务。 */
@Service
public class DefaultTaskApplicationService implements TaskApplicationService {
    private final CurrentActors actors;
    private final Db db;
    private final TaskDispatchService dispatch;
    private final TaskLifecycleService lifecycle;
    private final TaskRevisionService revisions;
    private final TaskQueryService queries;
    private final ReviewApplicationService reviews;
    public DefaultTaskApplicationService(CurrentActors actors,Db db,TaskDispatchService dispatch,TaskLifecycleService lifecycle,TaskRevisionService revisions,TaskQueryService queries,ReviewApplicationService reviews) {
        this.actors=actors;this.db=db;this.dispatch=dispatch;this.lifecycle=lifecycle;this.revisions=revisions;this.queries=queries;this.reviews=reviews;
    }
    public Map<String,Object> list(ActorContext actor,Map<String,Object> q) {
        Db.fields(q,"cursor","limit","search","ownerId","date","period");
        return queries.list(actors.fresh(actor),new TaskQueryService.Query(integer(q,"cursor",0),integer(q,"limit",30),Db.str(q,"search"),optional(q,"ownerId"),optional(q,"date"),q.containsKey("period")?Db.str(q,"period"):"day"));
    }
    private static String optional(Map<String,Object> q,String name){String value=Db.str(q,name);return value.isBlank()?null:value;}
    private static int integer(Map<String,Object> q,String name,int fallback){if(!q.containsKey(name))return fallback;try{return Integer.parseInt(String.valueOf(q.get(name)));}catch(NumberFormatException e){throw ApiError.bad("INVALID_PAGE","分页参数无效");}}
    public Map<String,Object> get(ActorContext actor,String id) { return dispatch.read(actors.fresh(actor),id); }
    @Transactional public Map<String,Object> create(ActorContext actor,Map<String,Object> b,String key) { return dispatch.dispatch(actors.fresh(actor),b,key); }
    @Transactional public Map<String,Object> appendEvent(ActorContext actor,String id,Map<String,Object> b) { return lifecycle.apply(actors.fresh(actor),id,b); }
    @Transactional public Map<String,Object> revise(ActorContext context,String id,Map<String,Object> b) {
        Actor a=actors.fresh(context); var task=TaskAccess.readable(db,a,id,true); a.requireDispatch();
        if(!a.admin()&&!a.id().equals(task.get("issuer_id"))) throw ApiError.forbidden();
        Db.fields(b,"version","candidate","reason");
        if(((Number)task.get("version")).intValue()!=Db.version(b)||TaskStateMachine.Phase.parse(Db.str(task,"phase")).terminal()) throw ApiError.conflict();
        var candidate=revisions.validateGeneric(db,a,task,db.read(b.get("candidate")));
        return reviews.create(a,"TASK",id,Db.version(b),db.read(task.get("body")),candidate,Db.required(b,"reason"));
    }
    @Transactional public Map<String,Object> requestReassignment(ActorContext context,String id,Map<String,Object> b) {
        Actor a=actors.fresh(context); var r=revisions.prepareReassignment(a,id,b);
        return reviews.create(a,"TASK_REASSIGN",id,r.version(),r.before(),r.candidate(),Db.required(b,"reason"));
    }
    @Transactional public Map<String,Object> requestReschedule(ActorContext context,String id,Map<String,Object> b) {
        Actor a=actors.fresh(context); var r=revisions.prepareReschedule(a,id,b);
        return reviews.create(a,"TASK_RESCHEDULE",id,r.version(),r.before(),r.candidate(),Db.required(b,"reason"));
    }
}
