package cn.workpanel.module.dashboard.application;

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
public class DashboardReviewedRevisionApplication implements ReviewedRevisionApplication {
    private final Db db;

    public DashboardReviewedRevisionApplication(Db db) { this.db=db;  }
    public Set<String> kinds() { return Set.of("COMPANY_ITEM"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "COMPANY_ITEM" -> {
                if(!applicant.global()) throw ApiError.forbidden(); db.one("SELECT id FROM companies WHERE id=? FOR UPDATE",approver.company());
                boolean pinned=Boolean.TRUE.equals(c.get("pinned")),archived=Boolean.TRUE.equals(c.get("archived"));
                if(pinned&&!archived&&db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND pinned AND NOT archived AND id<>?",approver.company(),target)>=10) throw ApiError.bad("PIN_LIMIT","最多置顶十项");
                if(v==0) db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned,archived,position) VALUES (?,?,?,'COMPANY',?,?::jsonb,?,?,?)",target,approver.company(),applicant.id(),c.get("title"),db.write(c),pinned,archived,c.getOrDefault("position",0));
                else Db.conflict(db.update("UPDATE dashboard_items SET title=?,body=?::jsonb,pinned=?,archived=?,position=?,version=version+1 WHERE id=? AND company_id=? AND version=?",c.get("title"),db.write(c),pinned,archived,c.getOrDefault("position",0),target,approver.company(),v));
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
    private static Object nullable(Map<String,Object> c,String key) { String value=Db.str(c,key); return value.isBlank()?null:value; }
}
