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
    public Set<String> kinds() { return Set.of("TASK","TASK_REASSIGN","TASK_RESCHEDULE","TASK_CREATE","TASK_DELETE"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "TASK_CREATE" -> {
                applicant.requireDispatch();
                if(!db.rows("SELECT id FROM tasks WHERE id=?",target).isEmpty()) throw ApiError.conflict();
                var draft=TaskDraftNormalizer.normalize(c); TaskParticipants.validate(db,applicant,draft); TaskLabels.validate(db,applicant,draft);
                TaskAttachments.verify(db,applicant,null,draft.attachments());
                db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version) VALUES (?,?,?,?,?,?::timestamptz,?::timestamptz,?::jsonb,'DISPATCHED',1)",
                        target,applicant.company(),draft.ownerId(),applicant.id(),draft.title(),draft.startAt(),draft.deadline(),db.write(draft.body()));
                TaskParticipants.assign(db,applicant,target,draft); TaskLabels.replace(db,applicant,target,draft);
                TaskAttachments.bind(db,applicant,target,draft.attachments(),false);
                TaskTimeline.append(db,applicant,target,"DISPATCHED",draft.body(),null,"DISPATCHED",1);
                db.audit(applicant,"TASK_CREATED_BY_REVIEW",target,Map.of(),draft.body(),reason);
            }
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
            case "TASK_DELETE" -> {
                var task=db.one("SELECT * FROM tasks WHERE id=? AND company_id=? FOR UPDATE",target,approver.company());
                if(!applicant.id().equals(task.get("issuer_id"))&&!applicant.admin()) throw ApiError.forbidden();
                taskRevisions.applyDeletion(db,applicant,task,v,reason);
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
}
