package cn.workpanel.module.organization;

import cn.workpanel.*;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.time.*;
import java.sql.Timestamp;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 使用独立公司与真实 HTTP/PostgreSQL 验证 week6 权限；不改公共集成夹具。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001"
})
class Week6AccessIntegrationTest extends MemberBHttpSupport {
    @Test void approvedRoleChangeRevokesAllOldSessionsButRejectedChangeDoesNot() throws Exception {
        var rejected=revision(director,Map.of("role","EMPLOYEE"));
        var pending=call(200,"GET","/reviews/"+rejected.get("id").asText(),admin,null);
        String judge=pending.get("steps").get(0).get("reviewer_id").asText();
        call(200,"POST","/reviews/"+rejected.get("id").asText()+"/decision",judge,Map.of("approve",false,"reason","保留角色","expectedVersion",pending.get("expected_version").asInt()));
        call(200,"GET","/auth/me",director,null);
        var accepted=revision(director,Map.of("role","EMPLOYEE"));
        approve(accepted.get("id").asText(),admin);
        assertEquals(0,db.count("SELECT count(*) FROM sessions WHERE user_id=?",director));
        call(401,"GET","/auth/me",director,null);
        call(401,"GET","/admin/workspace/auth/me",director,null);
    }
    @Test void workspaceDenialsArePersistedWithoutCredentialsOrPayloads() throws Exception {
        var missing=call(401,"GET","/admin/workspace/auth/me?secret=never-store-this","missing",null);
        var denied=call(403,"GET","/admin/workspace/auth/me",employee,null);
        var anonymous=db.one("SELECT * FROM workspace_access_audit WHERE trace_id=?",missing.get("traceId").asText());
        assertNull(anonymous.get("actor_id")); assertEquals(401,((Number)anonymous.get("status")).intValue());
        var authenticated=db.one("SELECT * FROM workspace_access_audit WHERE trace_id=?",denied.get("traceId").asText());
        assertEquals(employee,authenticated.get("actor_id")); assertEquals(company,authenticated.get("company_id"));
        assertEquals("ADMIN_WORKSPACE",authenticated.get("endpoint"));
        assertFalse(db.write(anonymous).contains("never-store-this"));
        assertFalse(db.write(authenticated).contains(tokens.get(employee)));
    }
    @Test void publicCommentsKeepScopeAndReplyNotificationsAtomic() throws Exception {
        String id=log(employee,true,Instant.now().minusSeconds(90000));
        var comment=call(200,"POST","/logs/"+id+"/comments",director,Map.of("text","公开评论"));
        String parent=comment.get("id").asText();
        var reply=call(200,"POST","/logs/"+id+"/comments",employee,Map.of("text","回复上级","parentId",parent));
        assertEquals(parent,reply.get("parent_id").asText());
        assertEquals(2,call(200,"GET","/logs/"+id+"/comments",founder,null).size());
        assertEquals(2,db.count("SELECT count(*) FROM outbox_events WHERE dedup_key LIKE ?","comment:"+reply.get("id").asText()+":%"));
        long events=db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id);
        call(404,"POST","/logs/"+id+"/comments",colleague,Map.of("text","同级不可见"));
        call(404,"GET","/logs/"+id+"/comments",foreign,null);
        call(400,"POST","/logs/"+id+"/comments",employee,Map.of("text"," "));
        call(400,"POST","/logs/"+id+"/comments",employee,Map.of("text","x".repeat(2001)));
        String other=log(colleague,true,Instant.now());
        call(400,"POST","/logs/"+other+"/comments",director,Map.of("text","错误目标","parentId",parent));
        assertEquals(events,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
        assertEquals(2,db.count("SELECT count(*) FROM log_comments WHERE log_id=?",id));
        db.update("UPDATE users SET role='EMPLOYEE' WHERE id=?",director);
        var after=call(200,"POST","/logs/"+id+"/comments",employee,Map.of("text","撤权后不通知","parentId",parent));
        assertEquals(1,db.count("SELECT count(*) FROM outbox_events WHERE dedup_key LIKE ?","comment:"+after.get("id").asText()+":%"));
        db.update("UPDATE daily_logs SET submitted=false WHERE id=?",id);
        call(403,"POST","/logs/"+id+"/comments",employee,Map.of("text","草稿"));
        call(404,"GET","/logs/"+id+"/comments",founder,null);
    }
    @Test void taskAuditIncludesReviewAndFiltersBeforePagination() throws Exception {
        String task=Db.id(), request=Db.id();
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES (?,?,?,?,?,now()+interval '1 day','{}')",task,company,employee,admin,"审计任务");
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES (?,?,?,'TASK',?,1,'{}','{}','审核测试')",request,company,admin,task);
        Actor actor=Actor.from(db.one("SELECT * FROM users WHERE id=?",admin));
        db.audit(actor,"TASK_DISPATCHED",task,Map.of(),Map.of("title","审计任务"),"派发");
        db.audit(actor,"REVIEW_REQUESTED",request,Map.of(),Map.of("title","待批准"),"申请");
        db.audit(actor,"REVISION_APPLIED",task,Map.of("title","旧"),Map.of("title","新"),"批准");
        db.audit(actor,"LOG_SUBMITTED",Db.id(),Map.of(),Map.of(),"不应返回");
        var page=call(200,"GET","/admin/workspace/organization/task-audit?limit=2",admin,null);
        assertEquals(3,page.get("total").asInt()); assertEquals(2,page.get("items").size());
        assertEquals(task,page.get("items").get(0).get("task_id").asText());
        assertEquals("REVISION_APPLIED",page.get("items").get(0).get("type").asText());
        assertEquals(1,call(200,"GET","/organization/task-audit?cursor=2&limit=2&taskId="+task,admin,null).get("items").size());
        assertEquals(0,call(200,"GET","/organization/task-audit?taskId="+Db.id(),admin,null).get("total").asInt());
        String otherAdmin=user(Db.str(db.one("SELECT company_id FROM users WHERE id=?",foreign),"company_id"),Db.str(db.one("SELECT department_id FROM users WHERE id=?",foreign),"department_id"),"","ADMIN",false);
        assertEquals(0,call(200,"GET","/organization/task-audit?taskId="+task,otherAdmin,null).get("total").asInt());
        call(403,"GET","/organization/task-audit",founder,null);
        call(403,"GET","/admin/workspace/organization/task-audit",employee,null);
        call(400,"GET","/organization/task-audit?cursor=-1",admin,null);
    }
    String log(String owner,boolean submitted,Instant time) {
        String id=Db.id();
        String c=Db.str(db.one("SELECT company_id FROM users WHERE id=?",owner),"company_id");
        db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES (?,?,?,CURRENT_DATE,?::jsonb,?,?)",id,c,owner,"{\"work\":\"week6 searchable work\"}",submitted,time==null?null:Timestamp.from(time));
        return id;
    }
    @Test void contentEditingUsesServerWindowAndCannotBeExtended() throws Exception {
        String id=log(employee,true,Instant.now().minusSeconds(86340));
        var first=db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at");
        var detail=call(200,"GET","/logs/"+id,employee,null);
        assertTrue(detail.get("canEdit").asBoolean()); assertFalse(detail.get("canWithdraw").asBoolean());
        call(403,"PUT","/logs/"+id+"/content",admin,Map.of("version",1,"work","代改"));
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("version",1,"work","updated"));
        assertEquals(first,db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at"));
        db.update("UPDATE daily_logs SET submitted_at=now()-interval '25 hours' WHERE id=?",id);
        assertEquals("LOG_EDIT_WINDOW_EXPIRED",call(409,"PUT","/logs/"+id+"/content",employee,Map.of("version",2,"work","过期" )).get("code").asText());
        call(400,"PUT","/logs/"+id+"/content",employee,Map.of("version",2,"work","伪造","submittedAt",Instant.now().toString()));
        assertEquals("updated",call(200,"GET","/logs/"+id,employee,null).get("body").get("work").asText());
    }
    @Test void submittedContentNeverReturnsToDraftOrResetsFirstTimestamp() throws Exception {
        String id=log(employee,true,Instant.now().minusSeconds(100));
        var first=db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at");
        call(409,"PUT","/logs/draft",employee,Map.of("businessDate",LocalDate.now(ZoneId.of("Asia/Shanghai")).toString(),"version",1,"body",Map.of("work","绕过正文入口")));
        call(409,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("version",1,"work","直接编辑"));
        assertEquals(first,db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at"));
        assertTrue(call(200,"GET","/logs/"+id,director,null).get("submitted").asBoolean());
    }
    @Test void departmentSearchGroupingAndPrivacy() throws Exception {
        String own=log(employee,true,Instant.now()); log(colleague,false,null); log(outside,true,Instant.now()); log(foreign,true,Instant.now());
        var result=call(200,"GET","/logs/subordinates?departmentId="+department+"&search=searchable&date="+LocalDate.now(),director,null);
        assertEquals(1,result.get("total").asInt()); assertEquals(1,result.get("groups").size());
        assertEquals(own,result.get("items").get(0).get("id").asText());
        assertEquals(department,result.get("items").get(0).get("department").get("id").asText());
        assertEquals(employee,result.get("items").get(0).get("author").get("id").asText());
        call(403,"GET","/logs/subordinates?departmentId="+otherDepartment,director,null);
        call(404,"GET","/logs/subordinates?departmentId="+Db.id(),director,null);
        assertEquals(0,call(200,"GET","/logs/subordinates?search=absent",director,null).get("total").asInt());
        assertEquals(2,call(200,"GET","/logs/subordinates",admin,null).get("groups").size());
        call(403,"GET","/logs/subordinates",employee,null);
        call(400,"GET","/logs/subordinates?search="+"a".repeat(101),director,null);
    }
    @Test void adminWorkspaceRejectsFounderEmployeeAndRevokedSessionWithoutBreakingMobile() throws Exception {
        call(200,"GET","/admin/workspace/auth/me",admin,null);
        call(200,"GET","/admin/workspace/organization/audit",admin,null);
        call(200,"GET","/admin/workspace/ai-memories?domain=PERSONAL",admin,null);
        for(String who:List.of(employee,founder)) {
            call(403,"GET","/admin/workspace/auth/me",who,null);
            call(200,"GET","/auth/me",who,null);
        }
        db.update("UPDATE users SET role='EMPLOYEE' WHERE id=?",admin);
        call(403,"GET","/admin/workspace/auth/me",admin,null);
        db.update("UPDATE users SET status='DISABLED' WHERE id=?",admin);
        call(401,"GET","/admin/workspace/auth/me",admin,null);
        call(401,"GET","/admin/workspace/auth/me","missing",null);
    }
}
