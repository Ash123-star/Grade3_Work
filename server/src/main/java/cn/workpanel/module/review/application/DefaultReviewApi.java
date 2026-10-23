package cn.workpanel.module.review.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.review.api.ReviewApi;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.Map;

/** 复核公共适配器；申请仍使用领域用例验证后的候选，不提供 AI 审批工具。 */
@Service
public class DefaultReviewApi implements ReviewApi {
    private final ReviewApplicationService service;private final CurrentActors actors;private final Db db;
    private final cn.workpanel.module.task.api.TaskApi tasks;
    public DefaultReviewApi(ReviewApplicationService service,CurrentActors actors,Db db,cn.workpanel.module.task.api.TaskApi tasks){this.service=service;this.actors=actors;this.db=db;this.tasks=tasks;}
    @Transactional public Map<String,Object> create(ActorContext a,Map<String,Object> b){
        actors.fresh(a);Db.fields(b,"kind","targetId","request");String target=Db.required(b,"targetId");var request=db.read(b.get("request"));
        return switch(Db.required(b,"kind")){
            case "TASK"->tasks.revise(a,target,request);
            case "TASK_REASSIGN"->tasks.requestReassignment(a,target,request);
            case "TASK_RESCHEDULE"->tasks.requestReschedule(a,target,request);
            default->throw ApiError.bad("DOMAIN_APPLICATION_REQUIRED","请通过对应业务提交复核申请");
        };
    }
    public Map<String,Object> get(ActorContext a,String id){return service.get(actors.fresh(a),id);}
    @Transactional public Map<String,Object> decide(ActorContext a,String id,boolean approve,String reason){return service.decide(actors.fresh(a),id,approve,reason);}
}
