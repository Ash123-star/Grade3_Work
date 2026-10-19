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
    Map<String,Object> revision(int version) { return Map.of("version",version,"reason","更正","body",Map.of("work","updated")); }
    @Test void timeWindowUsesServerTimeAndAllowsLateApproval() throws Exception {
        String id=log(employee,true,Instant.now().minusSeconds(86340));
        var detail=call(200,"GET","/logs/"+id,employee,null);
        assertTrue(detail.get("canEdit").asBoolean()); assertTrue(detail.get("canWithdraw").asBoolean());
        assertFalse(detail.get("editableUntil").isNull());
        assertEquals(department,detail.get("department").get("id").asText());
        assertEquals(employee,detail.get("author").get("id").asText());
        var pending=call(200,"POST","/logs/"+id+"/revisions",employee,revision(1));
        db.update("UPDATE daily_logs SET submitted_at=now()-interval '25 hours' WHERE id=?",id);
        assertEquals("LOG_EDIT_WINDOW_EXPIRED",call(409,"POST","/logs/"+id+"/revisions",employee,revision(1)).get("code").asText());
        call(409,"POST","/logs/"+id+"/revisions",admin,revision(1));
        call(409,"POST","/logs/"+id+"/withdraw",employee,Map.of("version",1,"reason","撤回"));
        approve(pending.get("id").asText(),employee);
        assertEquals("updated",call(200,"GET","/logs/"+id,employee,null).get("body").get("work").asText());
        assertFalse(call(200,"GET","/logs/"+id,employee,null).get("canEdit").asBoolean());
        call(400,"POST","/logs/"+id+"/revisions",employee,Map.of("version",2,"body",Map.of("work","x"),"reason","x","submittedAt",Instant.now().toString()));
    }
    @Test void withdrawalAndResubmissionKeepFirstTimestampAndInvalidatePendingRevision() throws Exception {
        String id=log(employee,true,Instant.now().minusSeconds(100));
        var start=db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at");
        var pending=call(200,"POST","/logs/"+id+"/revisions",employee,revision(1));
        call(403,"POST","/logs/"+id+"/withdraw",admin,Map.of("version",1,"reason","非本人"));
        call(200,"POST","/logs/"+id+"/withdraw",employee,Map.of("version",1,"reason","补充"));
        call(404,"GET","/logs/"+id,director,null);
        call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",2));
        assertEquals(start,db.one("SELECT submitted_at FROM daily_logs WHERE id=?",id).get("submitted_at"));
        var review=call(200,"GET","/reviews/"+pending.get("id").asText(),employee,null);
        var steps=review.get("steps");
        for(int i=0;i<steps.size();i++) call(i==steps.size()-1?409:200,"POST","/reviews/"+pending.get("id").asText()+"/decision",steps.get(i).get("reviewer_id").asText(),Map.of("approve",true));
        assertEquals("week6 searchable work",call(200,"GET","/logs/"+id,employee,null).get("body").get("work").asText());
        db.update("UPDATE daily_logs SET submitted=false,submitted_at=now()-interval '25 hours' WHERE id=?",id);
        call(409,"PUT","/logs/draft",employee,Map.of("businessDate",LocalDate.now().toString(),"version",3,"body",Map.of("work","reset")));
        call(409,"POST","/logs/"+id+"/submit",employee,Map.of("version",3));
    }
    @Test void departmentSearchGroupingAndPrivacy() throws Exception {
        String own=log(employee,true,Instant.now()); log(colleague,false,null); log(outside,true,Instant.now()); log(foreign,true,Instant.now());
        var result=call(200,"GET","/logs/subordinates?departmentId="+department+"&search=searchable&date="+LocalDate.now(),director,null);
        assertEquals(1,result.get("total").asInt()); assertEquals(1,result.get("groups").size());
        assertEquals(own,result.get("items").get(0).get("id").asText());
        assertEquals(department,result.get("items").get(0).get("department").get("id").asText());
        assertEquals(employee,result.get("items").get(0).get("author").get("id").asText());
        for(String d:List.of(otherDepartment,Db.id())) assertEquals(0,call(200,"GET","/logs/subordinates?departmentId="+d,director,null).get("total").asInt());
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
