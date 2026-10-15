package cn.workpanel.module.log.application;

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
public class LogReviewedRevisionApplication implements ReviewedRevisionApplication {
    private final Db db;

    public LogReviewedRevisionApplication(Db db) { this.db=db;  }
    public Set<String> kinds() { return Set.of("LOG"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "LOG" -> {
                var log=db.one("SELECT * FROM daily_logs WHERE id=? AND company_id=? FOR UPDATE",target,approver.company()); if(!applicant.id().equals(log.get("owner_id"))&&!applicant.admin()) throw ApiError.forbidden();
                Business.validateLog(db,applicant,c);
                Db.conflict(db.update("UPDATE daily_logs SET body=?::jsonb,version=version+1 WHERE id=? AND submitted AND version=?",db.write(c),target,v));
                db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,?,?::jsonb)",approver.company(),target,v+1,db.write(c));
                LogTaskLinks.validateAndSync(db, applicant, target, c);
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
    private static Object nullable(Map<String,Object> c,String key) { String value=Db.str(c,key); return value.isBlank()?null:value; }
}
