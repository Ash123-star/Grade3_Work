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
    private static final java.util.concurrent.atomic.AtomicInteger CARD_SERIAL=new java.util.concurrent.atomic.AtomicInteger(1);
    private static String card() { String prefix="11010519900101"+String.format("%03d",CARD_SERIAL.getAndIncrement()*2);int[] weights={7,9,10,5,8,4,2,1,6,3,7,9,10,5,8,4,2};int sum=0;for(int i=0;i<17;i++)sum+=(prefix.charAt(i)-'0')*weights[i];return prefix+"10X98765432".charAt(sum%11); }
    Map<String,Object> employeeCommand() {
        db.update("UPDATE users SET business_position='GENERAL_MANAGER' WHERE id=?",admin);
        String team=Db.id();db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,'测试组')",team,company,department);
        var command=new LinkedHashMap<String,Object>(Map.of("account","console-"+Db.id(),"password","Initial-password-2026","phone","138"+String.format("%08d",java.util.concurrent.ThreadLocalRandom.current().nextInt(100000000)),"name","新同事","departmentId",department,"teamId",team,"managerId",admin));command.put("gender","女");command.put("idCardNumber",card());return command;
    }
    @Test void createsEmployeeAndEnforcesPasswordChangeAcrossBusinessEntry() throws Exception {
        var command=employeeCommand();var created=call(200,"POST","/admin/console/employees",admin,command);String id=created.get("id").asText();
        assertEquals("EMPLOYEE",created.get("role").asText());assertEquals("ACTIVE",created.get("status").asText());assertTrue(created.get("must_change_password").asBoolean());assertFalse(created.has("password_hash"));assertFalse(created.has("password"));
        assertEquals(1,db.count("SELECT count(*) FROM user_roles WHERE user_id=? AND role_id='EMPLOYEE'",id));
        assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE target_id=?",id));
        assertEquals(command.get("teamId"),db.one("SELECT team_id FROM users WHERE id=?",id).get("team_id"));
        var identity=db.one("SELECT gender,id_card_number FROM users WHERE id=?",id);assertEquals("女",identity.get("gender"));assertEquals(command.get("idCardNumber"),identity.get("id_card_number"));
        var directory=call(200,"GET","/admin/console/employees?search="+command.get("account"),admin,null).get("items").get(0);assertTrue(directory.get("has_id_card").asBoolean());assertFalse(directory.has("id_card_number"));assertEquals(java.time.LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).getYear()-1990,directory.get("age").asInt());
        assertEquals(command.get("managerId"),db.one("SELECT manager_id FROM reporting_relations WHERE employee_id=?",id).get("manager_id"));
        var audit=db.one("SELECT * FROM audit_records WHERE object_id=? AND type='EMPLOYEE_PROVISIONED'",id);assertFalse(db.write(audit).contains("Initial-password"));assertFalse(db.write(audit).contains(command.get("phone").toString()));
        var history=call(200,"GET","/admin/console/history",admin,null).get("items");assertTrue(history.size()>0);assertFalse(history.toString().contains(command.get("idCardNumber").toString()));
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
    @Test void filtersDepartmentAndRejectsInvalidReportingNodes() throws Exception {
        var valid=employeeCommand();var created=call(200,"POST","/admin/console/employees",admin,valid);
        var filtered=call(200,"GET","/admin/console/employees?departmentId="+department+"&search="+valid.get("account"),admin,null);
        assertEquals(1,filtered.get("total").asInt());assertEquals(created.get("id").asText(),filtered.get("items").get(0).get("id").asText());
        assertEquals(valid.get("teamId"),filtered.get("items").get(0).get("team_id").asText());
        var wrongTeam=employeeCommand();wrongTeam.put("departmentId",otherDepartment);call(404,"POST","/admin/console/employees",admin,wrongTeam);
        var wrongManager=employeeCommand();wrongManager.put("managerId",foreign);call(400,"POST","/admin/console/employees",admin,wrongManager);
        var ordinaryManager=employeeCommand();ordinaryManager.put("managerId",employee);call(400,"POST","/admin/console/employees",admin,ordinaryManager);
        var crossDepartmentManager=employeeCommand();crossDepartmentManager.put("managerId",user(company,otherDepartment,"","DIRECTOR",false));call(400,"POST","/admin/console/employees",admin,crossDepartmentManager);
        call(404,"GET","/admin/console/employees?departmentId=other-company-department",admin,null);
        assertEquals(0,db.count("SELECT count(*) FROM users WHERE account IN (?,?)",wrongTeam.get("account"),wrongManager.get("account")));
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
    @Test void webAdminEmployeeChangeAppliesImmediatelyAndKeepsVersionAudit() throws Exception {
        String newTeam=Db.id();db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,'直属关系验证组')",newTeam,company,otherDepartment);
        String otherManager=user(company,otherDepartment,"","DIRECTOR",false);
        String replacementCard="11010519491231002X";
        var revision=call(200,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","调岗","name","新姓名","departmentId",otherDepartment,"teamId",newTeam,"managerId",otherManager,"status","DISABLED","gender","女","idCardNumber",replacementCard));
        assertEquals("APPLIED",revision.get("status").asText());assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE kind='USER' AND target_id=?",employee));
        var changed=db.one("SELECT * FROM users WHERE id=?",employee);assertEquals("新姓名",changed.get("name"));assertEquals(otherDepartment,changed.get("department_id"));assertEquals(newTeam,changed.get("team_id"));assertEquals("女",changed.get("gender"));assertEquals(replacementCard,changed.get("id_card_number"));assertEquals(otherManager,db.one("SELECT manager_id FROM reporting_relations WHERE employee_id=?",employee).get("manager_id"));call(401,"GET","/auth/me",employee,null);
        call(409,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","旧版本","name","重复"));
        assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='ADMIN_EMPLOYEE_UPDATED'",employee));
        assertFalse(db.write(db.one("SELECT before_value,after_value FROM audit_records WHERE object_id=? AND type='ADMIN_EMPLOYEE_UPDATED'",employee)).contains(replacementCard));
    }
    @Test void webAdminConfirmsPendingAccountWithTeamAndManager() throws Exception {
        String team=Db.id(),request=Db.id();
        db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,'确认归属组')",team,company,department);
        db.update("UPDATE users SET status='PENDING',team_id=NULL WHERE id=?",employee);
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES (?,?,?,?,?,1,'{}','{}','待确认')",request,company,employee,"MEMBERSHIP",employee);
        call(400,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","确认","status","ACTIVE","teamId",team,"managerId",""));
        var result=call(200,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","确认","status","ACTIVE","teamId",team,"managerId",founder));
        assertEquals("APPLIED",result.get("status").asText());
        var changed=db.one("SELECT status,team_id,employment_start_date FROM users WHERE id=?",employee);
        assertEquals("ACTIVE",changed.get("status"));assertEquals(team,changed.get("team_id"));assertNotNull(changed.get("employment_start_date"));
        assertEquals("SUPERSEDED",db.one("SELECT status FROM review_requests WHERE id=?",request).get("status"));
        var second=call(200,"POST","/admin/console/employees",admin,employeeCommand());String secondId=second.get("id").asText(),secondRequest=Db.id();
        db.update("UPDATE users SET status='PENDING' WHERE id=?",secondId);
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES (?,?,?,?,?,1,'{}','{}','待确认')",secondRequest,company,secondId,"MEMBERSHIP",secondId);
        call(200,"POST","/admin/console/employees/"+secondId+"/revisions",admin,Map.of("version",1,"reason","账号不予启用","status","DISABLED"));
        assertEquals("SUPERSEDED",db.one("SELECT status FROM review_requests WHERE id=?",secondRequest).get("status"));
    }
    @Test void staleMembershipReviewExplainsTargetVersionWithoutChangingAccount() throws Exception {
        String request=Db.id();
        db.update("UPDATE users SET status='PENDING',version=4 WHERE id=?",employee);
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,approval_mode) VALUES (?,?,?,?,?,1,'{}',?::jsonb,'确认归属','ADMIN_MEMBERSHIP')",request,company,employee,"MEMBERSHIP",employee,db.write(Map.of("departmentId",department)));
        db.update("INSERT INTO review_steps(request_id,reviewer_id,applicant_id,position,company_id) VALUES (?,?,?,1,?)",request,admin,employee,company);
        var detail=call(200,"GET","/admin/console/reviews/"+request,admin,null);
        assertTrue(detail.get("stale").asBoolean());assertEquals(1,detail.get("expected_version").asInt());assertEquals(4,detail.get("target_version").asInt());
        assertEquals(0,call(200,"GET","/admin/console/reviews",admin,null).get("total").asInt());
        call(409,"POST","/admin/console/reviews/"+request+"/decision",admin,Map.of("approve",true,"reason","确认","expectedVersion",1));
        assertEquals("PENDING",db.one("SELECT status FROM users WHERE id=?",employee).get("status"));
    }
    Map<String,Object> priority(String title) { return new LinkedHashMap<>(Map.of("title",title,"text","公司重点正文","pinned",true,"archived",false,"position",1,"version",0,"reason","新增事项")); }
    @Test void webAdminPriorityPublishesImmediatelyAndProtectsVersions() throws Exception {
        var request=call(200,"POST","/admin/console/priorities/revisions",admin,priority("重点事项"));String id=request.get("id").asText();
        assertEquals("APPLIED",request.get("status").asText());assertEquals(1,db.count("SELECT count(*) FROM dashboard_items WHERE id=?",id));
        var mobile=call(200,"GET","/dashboard/company",employee,null);assertEquals("重点事项",mobile.get("items").get(0).get("title").asText());
        var change=priority("修订重点");change.put("id",id);change.put("version",1);
        call(200,"POST","/admin/console/priorities/revisions",admin,change);
        call(409,"POST","/admin/console/priorities/revisions",admin,change);
        assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE kind='COMPANY_ITEM' AND target_id=?",id));
        var foreignActorCompany=db.one("SELECT company_id FROM users WHERE id=?",foreign).get("company_id");String foreignAdmin=user(foreignActorCompany.toString(),db.one("SELECT department_id FROM users WHERE id=?",foreign).get("department_id").toString(),"","ADMIN",false);
        assertEquals(0,call(200,"GET","/admin/console/priorities",foreignAdmin,null).get("total").asInt());call(404,"POST","/admin/console/priorities/revisions",foreignAdmin,change);
    }
    @Test void rejectsEleventhPinnedPriorityAtomically() throws Exception {
        for(int i=0;i<10;i++) db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned) VALUES (?,?,?,'COMPANY',?,'{}',true)",Db.id(),company,admin,"事项"+i);
        call(400,"POST","/admin/console/priorities/revisions",admin,priority("第十一项"));
        assertEquals(10,db.count("SELECT count(*) FROM dashboard_items WHERE company_id=?",company));
    }

    @Test void explainsEveryDuplicateFieldWithoutLeakingExistingIdentity() throws Exception {
        var original=employeeCommand();call(200,"POST","/admin/console/employees",admin,original);
        for(String field:List.of("account","phone","idCardNumber")) {
            var candidate=employeeCommand();candidate.put(field,original.get(field));
            var error=call(409,"POST","/admin/console/employees",admin,candidate);
            assertTrue(error.get("fieldErrors").has(field));assertEquals(1,error.get("fieldErrors").size());
            assertFalse(error.toString().contains(original.get("idCardNumber").toString()));
        }
        var error=call(409,"POST","/admin/console/employees",admin,original);
        assertEquals(3,error.get("fieldErrors").size());
        assertEquals(1,db.count("SELECT count(*) FROM users WHERE account=?",original.get("account")));
    }
    @Test void directorCanReportAcrossDepartmentsToBusinessExecutiveButNotBareAdministrator() throws Exception {
        String boss=user(company,otherDepartment,"","FOUNDER",false);
        var updated=call(200,"POST","/admin/console/employees/"+director+"/revisions",admin,Map.of("version",1,"reason","明确汇报关系","managerId",boss));
        assertEquals("APPLIED",updated.get("status").asText());
        assertEquals(boss,db.one("SELECT manager_id FROM reporting_relations WHERE employee_id=?",director).get("manager_id"));
        call(400,"POST","/admin/console/employees/"+director+"/revisions",admin,Map.of("version",2,"reason","错误上级","managerId",admin));
        db.update("UPDATE users SET business_position='GENERAL_MANAGER' WHERE id=?",outside);
        call(200,"POST","/admin/console/employees/"+director+"/revisions",admin,Map.of("version",2,"reason","总经理负责","managerId",outside));
        var row=call(200,"GET","/admin/console/employees?search=org-"+director,admin,null).get("items").get(0);
        assertEquals("GENERAL_MANAGER",row.get("manager_business_position").asText());assertFalse(row.has("id_card_number"));
        assertEquals("DIRECTOR",row.get("role").asText());
    }
    @Test void changingBusinessPositionKeepsRoleAndVersionProtection() throws Exception {
        call(200,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","任命副总","businessPosition","DEPUTY_GENERAL_MANAGER","managerId",founder));
        var row=db.one("SELECT business_position,role,version FROM users WHERE id=?",employee);
        assertEquals("DEPUTY_GENERAL_MANAGER",row.get("business_position"));assertEquals("EMPLOYEE",row.get("role"));assertEquals(2,row.get("version"));
        call(409,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",1,"reason","过期修改","businessPosition","NONE","managerId",founder));
        assertEquals("DEPUTY_GENERAL_MANAGER",db.one("SELECT business_position FROM users WHERE id=?",employee).get("business_position"));
        // A director reporting to the executive cannot be selected as that executive's manager.
        db.update("INSERT INTO reporting_relations VALUES (?,?,?)",director,employee,company);
        db.update("UPDATE users SET business_position='GENERAL_MANAGER' WHERE id=?",director);
        call(400,"POST","/admin/console/employees/"+employee+"/revisions",admin,Map.of("version",2,"reason","循环应拒绝","managerId",director));
    }
    @Test void identityUpdateExcludesSelfButRejectsAnotherEmployeeCard() throws Exception {
        var first=employeeCommand();String one=call(200,"POST","/admin/console/employees",admin,first).get("id").asText();
        var second=employeeCommand();String two=call(200,"POST","/admin/console/employees",admin,second).get("id").asText();
        call(200,"POST","/admin/console/employees/"+one+"/revisions",admin,Map.of("version",1,"reason","核对资料","idCardNumber",first.get("idCardNumber")));
        var error=call(409,"POST","/admin/console/employees/"+one+"/revisions",admin,Map.of("version",2,"reason","重复资料应拒绝","idCardNumber",second.get("idCardNumber")));
        assertTrue(error.get("fieldErrors").has("idCardNumber"));
        assertEquals(2,db.one("SELECT version FROM users WHERE id=?",one).get("version"));
    }
    @Test void concurrentDuplicateInsertCreatesOnlyOneAccount() throws Exception {
        var first=employeeCommand();var second=employeeCommand();second.put("phone",first.get("phone"));
        var gate=new java.util.concurrent.CountDownLatch(1);
        try(var executor=java.util.concurrent.Executors.newFixedThreadPool(2)) {
            var a=executor.submit(()->{gate.await();return postEmployee(first);});var b=executor.submit(()->{gate.await();return postEmployee(second);});gate.countDown();
            var results=List.of(a.get(30,java.util.concurrent.TimeUnit.SECONDS),b.get(30,java.util.concurrent.TimeUnit.SECONDS));
            assertEquals(1,results.stream().filter(r->r.statusCode()==200).count());
            var conflict=results.stream().filter(r->r.statusCode()==409).findFirst().orElseThrow();
            assertTrue(JSON.readTree(conflict.body()).get("fieldErrors").has("phone"));
        }
        assertEquals(1,db.count("SELECT count(*) FROM users WHERE phone=?",first.get("phone")));
    }
    java.net.http.HttpResponse<String> postEmployee(Map<String,Object> command) throws Exception {
        return http.send(java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:"+port+"/api/admin/console/employees")).timeout(java.time.Duration.ofSeconds(20)).header("Authorization","Bearer "+tokens.get(admin)).header("Content-Type","application/json").POST(java.net.http.HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(command))).build(),java.net.http.HttpResponse.BodyHandlers.ofString());
    }

    @Test void openApiDocumentsOptionalFieldErrorsAndManagerOptions() throws Exception {
        var contract=call(200,"GET","/openapi",admin,null);
        var error=contract.get("components").get("schemas").get("Error");
        assertTrue(error.get("properties").has("fieldErrors"));
        assertFalse(error.get("required").toString().contains("fieldErrors"));
        assertTrue(contract.get("paths").has("/api/admin/console/managers"));
        assertTrue(contract.get("paths").has("/api/admin/console/teams"));
    }
}
