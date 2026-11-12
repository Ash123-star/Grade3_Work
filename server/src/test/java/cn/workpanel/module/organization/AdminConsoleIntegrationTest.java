package cn.workpanel.module.organization;

import cn.workpanel.*;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 管理入口到真实HTTP、认证、审核和PostgreSQL；复用隔离公司夹具。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001"
})
class AdminConsoleIntegrationTest extends MemberBHttpSupport {
    Map<String,Object> employeeCommand() {
        return new LinkedHashMap<>(Map.of("account","console-"+Db.id(),"password","Initial-password-2026","phone","138"+String.format("%08d",java.util.concurrent.ThreadLocalRandom.current().nextInt(100000000)),"name","新同事","departmentId",department));
    }
    @Test void createsEmployeeAndEnforcesPasswordChangeAcrossBusinessEntry() throws Exception {
        var command=employeeCommand();var created=call(200,"POST","/admin/console/employees",admin,command);String id=created.get("id").asText();
        assertEquals("EMPLOYEE",created.get("role").asText());assertEquals("ACTIVE",created.get("status").asText());assertTrue(created.get("must_change_password").asBoolean());assertFalse(created.has("password_hash"));assertFalse(created.has("password"));
        assertEquals(1,db.count("SELECT count(*) FROM user_roles WHERE user_id=? AND role_id='EMPLOYEE'",id));
        assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE target_id=?",id));
        var audit=db.one("SELECT * FROM audit_records WHERE object_id=? AND type='EMPLOYEE_PROVISIONED'",id);assertFalse(db.write(audit).contains("Initial-password"));assertFalse(db.write(audit).contains(command.get("phone").toString()));
        var login=call(200,"POST","/auth/login",admin,Map.of("account",command.get("account"),"password",command.get("password")));tokens.put(id,login.get("token").asText());
        call(403,"GET","/dashboard",id,null);
        call(200,"POST","/auth/password",id,Map.of("oldPassword",command.get("password"),"newPassword","Changed-password-2026"));
        call(401,"GET","/auth/me",id,null);
        var again=call(200,"POST","/auth/login",admin,Map.of("account",command.get("account"),"password","Changed-password-2026"));tokens.put(id,again.get("token").asText());
        call(200,"GET","/dashboard",id,null);call(403,"GET","/admin/console/employees",id,null);
    }
    @Test void rejectsDuplicateAndInjectionWithoutPartialWrites() throws Exception {
        var c=employeeCommand();call(200,"POST","/admin/console/employees",admin,c);
        long auditCount=db.count("SELECT count(*) FROM audit_records WHERE company_id=?",company);
        call(409,"POST","/admin/console/employees",admin,c);
        var duplicatePhone=new LinkedHashMap<>(c);duplicatePhone.put("account","other-"+Db.id());call(409,"POST","/admin/console/employees",admin,duplicatePhone);
        var forged=employeeCommand();forged.put("role","ADMIN");call(400,"POST","/admin/console/employees",admin,forged);
        var foreignDepartment=employeeCommand();foreignDepartment.put("departmentId",db.one("SELECT department_id FROM users WHERE id=?",foreign).get("department_id"));call(404,"POST","/admin/console/employees",admin,foreignDepartment);
        assertEquals(1,db.count("SELECT count(*) FROM users WHERE account=?",c.get("account")));assertEquals(auditCount,db.count("SELECT count(*) FROM audit_records WHERE company_id=?",company));
    }
    @Test void deniesOtherRolesAndSeparatesCompaniesAndPagination() throws Exception {
        for(String who:List.of(employee,founder)) { call(403,"GET","/admin/console/employees",who,null);call(403,"POST","/admin/console/employees",who,employeeCommand()); }
        call(401,"GET","/admin/console/employees","missing",null);call(400,"GET","/admin/console/employees?limit=0",admin,null);
        call(400,"GET","/admin/console/employees?search="+"a".repeat(101),admin,null);
        db.update("UPDATE users SET status='DISABLED' WHERE id=?",employee);
        var page=call(200,"GET","/admin/console/employees?search="+employee,admin,null);assertEquals(1,page.get("total").asInt());assertEquals("DISABLED",page.get("items").get(0).get("status").asText());
        var foreignPage=call(200,"GET","/admin/console/employees?search="+foreign,admin,null);assertEquals(0,foreignPage.get("total").asInt());
        call(404,"POST","/admin/console/employees/"+foreign+"/revisions",admin,Map.of("version",1,"reason","测试","name","越权"));
    }
    @Test void employeeChangeAndDisableRequireIndependentApproval() throws Exception {
        var revision=call(200,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","调岗","name","新姓名","departmentId",otherDepartment,"status","DISABLED"));
        assertEquals("PENDING",revision.get("status").asText());assertEquals("ACTIVE",db.one("SELECT status FROM users WHERE id=?",employee).get("status"));
        call(403,"POST","/admin/console/reviews/"+revision.get("id").asText()+"/decision",admin,Map.of("approve",true,"reason","自审","expectedVersion",1));
        call(200,"POST","/admin/console/reviews/"+revision.get("id").asText()+"/decision",reviewer,Map.of("approve",true,"reason","同意","expectedVersion",1));
        var changed=db.one("SELECT * FROM users WHERE id=?",employee);assertEquals("新姓名",changed.get("name"));assertEquals(otherDepartment,changed.get("department_id"));assertNull(changed.get("team_id"));call(401,"GET","/auth/me",employee,null);
    }
    Map<String,Object> priority(String title) { return new LinkedHashMap<>(Map.of("title",title,"text","公司重点正文","pinned",true,"archived",false,"position",1,"version",0,"reason","新增事项")); }
    @Test void priorityReviewPublishesSameContentAndProtectsVersions() throws Exception {
        var request=call(200,"POST","/admin/console/priorities/revisions",admin,priority("重点事项"));String id=request.get("target_id").asText();
        assertEquals(0,db.count("SELECT count(*) FROM dashboard_items WHERE id=?",id));approve(request.get("id").asText(),admin);
        var mobile=call(200,"GET","/dashboard/company",employee,null);assertEquals("重点事项",mobile.get("items").get(0).get("title").asText());
        var change=priority("修订重点");change.put("id",id);change.put("version",1);
        var first=call(200,"POST","/admin/console/priorities/revisions",admin,change);var stale=call(200,"POST","/admin/console/priorities/revisions",admin,change);approve(first.get("id").asText(),admin);
        call(409,"POST","/admin/console/reviews/"+stale.get("id").asText()+"/decision",reviewer,Map.of("approve",true,"expectedVersion",1,"reason","旧版本"));
        var foreignActorCompany=db.one("SELECT company_id FROM users WHERE id=?",foreign).get("company_id");String foreignAdmin=user(foreignActorCompany.toString(),db.one("SELECT department_id FROM users WHERE id=?",foreign).get("department_id").toString(),"","ADMIN",false);
        assertEquals(0,call(200,"GET","/admin/console/priorities",foreignAdmin,null).get("total").asInt());call(404,"POST","/admin/console/priorities/revisions",foreignAdmin,change);
    }
    @Test void rejectsEleventhPinnedPriorityAtomically() throws Exception {
        for(int i=0;i<10;i++) db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned) VALUES (?,?,?,'COMPANY',?,'{}',true)",Db.id(),company,admin,"事项"+i);
        var pending=call(200,"POST","/admin/console/priorities/revisions",admin,priority("第十一项"));
        call(400,"POST","/admin/console/reviews/"+pending.get("id").asText()+"/decision",reviewer,Map.of("approve",true,"expectedVersion",0,"reason","尝试通过"));
        assertEquals(10,db.count("SELECT count(*) FROM dashboard_items WHERE company_id=?",company));assertEquals("PENDING",call(200,"GET","/admin/console/reviews/"+pending.get("id").asText(),admin,null).get("status").asText());
    }
}
