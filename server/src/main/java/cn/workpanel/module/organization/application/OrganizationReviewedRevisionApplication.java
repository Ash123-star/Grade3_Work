package cn.workpanel.module.organization.application;

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
public class OrganizationReviewedRevisionApplication implements ReviewedRevisionApplication {
    private final Db db;

    public OrganizationReviewedRevisionApplication(Db db) { this.db=db;  }
    public Set<String> kinds() { return Set.of("POLICY","MEMBERSHIP","REVIEWER","USER","DEPARTMENT","TEAM"); }
    @Transactional(propagation=Propagation.MANDATORY)
    public void apply(String kind,ActorContext applicantContext,ActorContext approverContext,String target,int v,Map<String,Object> c,String reason) {
        Actor applicant=ReviewActors.actor(applicantContext),approver=ReviewActors.actor(approverContext);
        if(!applicant.company().equals(approver.company())) throw ApiError.forbidden();
        switch(kind) {
            case "POLICY" -> {
                applicant.requireAdmin();var old=db.one("SELECT review_policy FROM companies WHERE id=? FOR UPDATE",approver.company());
                var next=cn.workpanel.module.aiwork.domain.AuthorizationPolicy.from(c);var previous=cn.workpanel.module.aiwork.domain.AuthorizationPolicy.from(db.read(old.get("review_policy")));
                Db.conflict(db.update("UPDATE companies SET review_policy=?::jsonb,version=version+1,ai_authorization_revision=ai_authorization_revision+? WHERE id=? AND version=?",db.write(c),next.equals(previous)?0:1,approver.company(),v));
            }
            case "MEMBERSHIP" -> {
                db.one("SELECT id FROM departments WHERE id=? AND company_id=?",Db.required(c,"departmentId"),approver.company());
                java.time.LocalDate effectiveDate=java.time.LocalDate.now(java.time.ZoneId.of("Asia/Shanghai"));
                Db.conflict(db.update("UPDATE users SET status='ACTIVE',department_id=?,employment_start_date=COALESCE(employment_start_date,?::date),version=version+1 WHERE id=? AND company_id=? AND status='PENDING' AND version=?",c.get("departmentId"),effectiveDate,target,approver.company(),v));
            }
            case "REVIEWER" -> Db.conflict(db.update("UPDATE users SET company_reviewer=true,version=version+1 WHERE id=? AND company_id=? AND status='ACTIVE' AND version=?",target,approver.company(),v));
            case "USER" -> {
                applicant.requireAdmin(); OrganizationValidation.validateUser(db,approver.company(),target,c);
                String previousRole=Db.str(db.one("SELECT role FROM users WHERE id=? AND company_id=? FOR UPDATE",target,approver.company()),"role");
                Db.conflict(db.update("UPDATE users SET name=?,department_id=?,team_id=?,role=?,status=?,dispatch_enabled=?,company_reviewer=?,version=version+1 WHERE id=? AND company_id=? AND version=?",Db.required(c,"name"),nullable(c,"departmentId"),nullable(c,"teamId"),Db.required(c,"role"),Db.required(c,"status"),c.get("dispatchEnabled"),c.get("companyReviewer"),target,approver.company(),v));
                db.update("UPDATE user_roles SET role_id=? WHERE user_id=?",c.get("role"),target);
                db.update("DELETE FROM reporting_relations WHERE employee_id=?",target); if(!Db.str(c,"managerId").isBlank()) db.update("INSERT INTO reporting_relations VALUES (?,?,?)",target,c.get("managerId"),approver.company());
                if(c.get("status").equals("DISABLED")||!previousRole.equals(c.get("role"))) db.update("DELETE FROM sessions WHERE user_id=?",target);
            }
            case "DEPARTMENT","TEAM" -> {
                applicant.requireAdmin(); String table=kind.equals("TEAM")?"teams":"departments";
                if(kind.equals("TEAM")) db.one("SELECT id FROM departments WHERE id=? AND company_id=?",Db.required(c,"departmentId"),approver.company());
                if(v==0) {
                    if(kind.equals("TEAM")) db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?)",target,approver.company(),c.get("departmentId"),c.get("name"));
                    else db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",target,approver.company(),c.get("name"));
                } else {
                    // 已有人团队不能直接改部门，避免人员归属不同步。
                    if(kind.equals("TEAM")) { var team=db.one("SELECT * FROM teams WHERE id=? AND company_id=?",target,approver.company()); if(!team.get("department_id").equals(c.get("departmentId"))&&db.count("SELECT count(*) FROM users WHERE team_id=?",target)>0) throw ApiError.bad("TEAM_HAS_MEMBERS","先通过人员调岗移出团队"); }
                    Db.conflict(db.update("UPDATE "+table+" SET name=?,version=version+1 WHERE id=? AND company_id=? AND version=?",c.get("name"),target,approver.company(),v));
                    if(kind.equals("TEAM")) db.update("UPDATE teams SET department_id=? WHERE id=?",c.get("departmentId"),target);
                }
            }
            default -> throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        }
    }
    private static Object nullable(Map<String,Object> c,String key) { String value=Db.str(c,key); return value.isBlank()?null:value; }
}
