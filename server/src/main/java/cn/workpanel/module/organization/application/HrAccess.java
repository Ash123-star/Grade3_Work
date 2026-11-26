package cn.workpanel.module.organization.application;
import cn.workpanel.*;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
/** 公司级显式人事权限；岗位、直属上级与上传者身份均不授予合同权限。 */
@Service public class HrAccess {
 private final Db db; private final CurrentActors actors;
 public HrAccess(Db db,CurrentActors actors){this.db=db;this.actors=actors;}
 public Actor require(Actor request,boolean write){Actor a=actors.fresh(request);if(!allowed(a.company(),a.id(),write))throw ApiError.forbidden();return a;}
 public boolean allowed(String company,String user,boolean write){return db.count("SELECT count(*) FROM users u LEFT JOIN hr_grants g ON g.company_id=u.company_id AND g.user_id=u.id WHERE u.company_id=? AND u.id=? AND u.status='ACTIVE' AND NOT u.must_change_password AND (u.role='ADMIN' OR g.access="+(write?"'MANAGE'":"ANY(ARRAY['READ','MANAGE'])")+")",company,user)>0;}
 public boolean isContract(String attachment){return db.count("SELECT count(*) FROM employee_contracts WHERE attachment_id=?",attachment)>0;}
 public void attachment(Actor a,String id){if(isContract(id)){require(a,false);db.one("SELECT id FROM employee_contracts WHERE company_id=? AND attachment_id=?",a.company(),id);}}
}
