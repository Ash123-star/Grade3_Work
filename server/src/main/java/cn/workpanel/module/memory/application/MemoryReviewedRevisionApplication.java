package cn.workpanel.module.memory.application;

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
public class MemoryReviewedRevisionApplication implements ReviewedRevisionApplication {
    private final Db db;

    public MemoryReviewedRevisionApplication(Db db) { this.db=db;  }
    public Set<String> kinds() { return Set.of("MEMORY"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "MEMORY" -> {
                Memory memory=new Memory(db,new Business(db),null,null,false);
                memory.scope(applicant,Db.required(c,"domain"),Db.required(c,"scopeType"),Db.required(c,"scopeId"));
                var original=memory.item(applicant,target);
                if(!original.get("domain").equals("ORGANIZATION")) throw ApiError.forbidden();
                Db.conflict(db.update("UPDATE memory_items SET content=?,status='ACTIVE',version=version+1,updated_at=now() WHERE company_id=? AND id=? AND version=? AND status IN ('CANDIDATE','ACTIVE')",Db.required(c,"content"),approver.company(),target,v));
                memory.snapshot(approver.company(),target);
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
    private static Object nullable(Map<String,Object> c,String key) { String value=Db.str(c,key); return value.isBlank()?null:value; }
}
