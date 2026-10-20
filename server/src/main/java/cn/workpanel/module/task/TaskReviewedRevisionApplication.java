package cn.workpanel.module.task;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import cn.workpanel.module.organization.application.OrganizationValidation;
import cn.workpanel.module.log.LogTaskLinks;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Propagation;
import java.util.*;

/** 所属模块负责已审批候选的最终业务校验和写入；必须加入审核事务，失败整体回滚。 */
@Service
public class TaskReviewedRevisionApplication implements ReviewedRevisionApplication {
    private final Db db;
    private final TaskRevisionService taskRevisions;
    public TaskReviewedRevisionApplication(Db db,TaskRevisionService taskRevisions) { this.db=db; this.taskRevisions=taskRevisions; }
    public Set<String> kinds() { return Set.of("TASK","TASK_REASSIGN","TASK_RESCHEDULE"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "TASK" -> {
                var task=db.one("SELECT * FROM tasks WHERE id=? AND company_id=? FOR UPDATE",target,approver.company()); applicant.requireDispatch(); if(!applicant.id().equals(task.get("issuer_id"))&&!applicant.admin()) throw ApiError.forbidden(); if(Set.of("ARCHIVED","WITHDRAWN").contains(task.get("phase"))) throw ApiError.conflict();
                taskRevisions.applyGeneric(db,applicant,task,v,c);
            }
            case "TASK_REASSIGN" -> {
                var task=db.one("SELECT * FROM tasks WHERE id=? AND company_id=? FOR UPDATE",target,approver.company());
                if(!applicant.id().equals(task.get("issuer_id"))&&!applicant.admin()) throw ApiError.forbidden();
                taskRevisions.applyReassignment(db,applicant,task,v,c,reason);
            }
            case "TASK_RESCHEDULE" -> {
                var task=db.one("SELECT * FROM tasks WHERE id=? AND company_id=? FOR UPDATE",target,approver.company());
                if(!applicant.id().equals(task.get("issuer_id"))&&!applicant.admin()) throw ApiError.forbidden();
                taskRevisions.applyReschedule(db,applicant,task,v,c,reason);
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
    private static Object nullable(Map<String,Object> c,String key) { String value=Db.str(c,key); return value.isBlank()?null:value; }
}
