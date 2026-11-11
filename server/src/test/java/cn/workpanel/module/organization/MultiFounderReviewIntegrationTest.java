package cn.workpanel.module.organization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 多创始人免审与部门经理直属审批：禁止创始人池兜底及越权。夹具与组织验收共用。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class MultiFounderReviewIntegrationTest extends MemberBHttpSupport {
    @org.springframework.beans.factory.annotation.Autowired cn.workpanel.module.review.application.ReviewApplicationService reviews;

    /** 由创始人提交新增公司重点（创始人已有权限）；生效与否以 dashboard_items 是否写入判断。 */
    String founderRequest(String applicant, String title) {
        var actor = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", applicant));
        return (String) reviews.create(actor, "COMPANY_ITEM", cn.workpanel.Db.id(), 0, Map.of(), Map.of("title", title), "创始人互审测试").get("id");
    }
    boolean applied(String title) { return db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND title=?", company, title) == 1; }
    int expected(String id) { return ((Number) db.one("SELECT expected_version FROM review_requests WHERE id=?", id).get("expected_version")).intValue(); }
    String pendingReviewer(String id) {
        var rows = db.rows("SELECT reviewer_id FROM review_steps WHERE request_id=? AND state='PENDING'", id);
        return rows.isEmpty() ? null : (String) rows.getFirst().get("reviewer_id");
    }
    JsonNode decide(int status, String id, String who) throws Exception {
        return call(status, "POST", "/reviews/" + id + "/decision", who, Map.of("approve", true, "reason", "创始人复核", "expectedVersion", expected(id)));
    }

    @Test void singleFounderKeepsExemption() {
        String id = founderRequest(founder, "单创始人免审");
        var row = db.one("SELECT status,decision_source FROM review_requests WHERE id=?", id);
        assertEquals("APPROVED", row.get("status")); assertEquals("FOUNDER_EXEMPT", row.get("decision_source"));
        assertTrue(applied("单创始人免审"));
    }

    @Test void multipleFoundersKeepExemptionAndCannotApproveEachOther() throws Exception {
        String peer=user(company,department,"","FOUNDER",false);
        String id=founderRequest(founder,"多创始人免审");
        var detail=call(200,"GET","/reviews/"+id,founder,null);
        assertEquals("APPROVED",detail.get("status").asText());
        assertEquals("FOUNDER_EXEMPT",detail.get("decision_source").asText());
        assertFalse(detail.get("reviewer_selectable").asBoolean());
        assertNull(pendingReviewer(id)); assertTrue(applied("多创始人免审"));
        assertEquals(0,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_PENDING'",id));
        decide(409,id,peer);
        call(409,"GET","/reviews/"+id+"/reviewer-candidates",founder,null);
    }

    @Test void directorRoutesOnlyToAssignedFounderAndCannotChooseAnother() throws Exception {
        String other=user(company,department,"","FOUNDER",false);
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)",director,founder,company);
        String id=directorDeletion("部门经理直属审批");
        assertEquals(founder,pendingReviewer(id));
        assertEquals("DIRECT_MANAGER",call(200,"GET","/reviews/"+id,director,null).get("approval_mode").asText());
        call(403,"GET","/reviews/"+id,other,null); decide(403,id,other);
        call(409,"POST","/reviews/"+id+"/reviewer",director,Map.of("reviewerId",other,"expectedVersion",expected(id)));
        assertNotEquals("ARCHIVED",db.one("SELECT phase FROM tasks WHERE id=(SELECT target_id FROM review_requests WHERE id=?)",id).get("phase"));
        decide(200,id,founder); assertEquals("ARCHIVED",db.one("SELECT phase FROM tasks WHERE id=(SELECT target_id FROM review_requests WHERE id=?)",id).get("phase"));
        decide(409,id,founder);
    }

    @Test void concurrentDirectApprovalAppliesOnce() throws Exception {
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)",director,founder,company);
        String id=directorDeletion("一次生效");
        var body=Map.<String,Object>of("approve",true,"expectedVersion",expected(id));
        try(var pool=Executors.newFixedThreadPool(2)) {
            var a=pool.submit(()->send(founder,"/reviews/"+id+"/decision",body));
            var b=pool.submit(()->send(founder,"/reviews/"+id+"/decision",body));
            assertEquals(Set.of(200,409),Set.of(a.get(20,TimeUnit.SECONDS),b.get(20,TimeUnit.SECONDS)));
        }
        assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_APPROVED'",id));
        assertEquals(1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'",id));
    }
    @Test void retiredPeerCannotBeReactivated() throws Exception {
        String id=cn.workpanel.Db.id();
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status,approval_mode) VALUES (?,?,?,'COMPANY_ITEM',?,0,'{}','{}','old','SUPERSEDED','FOUNDER_PEER')",id,company,founder,cn.workpanel.Db.id());
        assertEquals("REVIEW_RULE_RETIRED",call(409,"POST","/reviews/"+id+"/reroute",founder,Map.of()).get("code").asText());
        call(409,"POST","/reviews/"+id+"/reviewer",founder,Map.of("reviewerId",admin,"expectedVersion",0));
        decide(409,id,admin);
        assertEquals(0,db.count("SELECT count(*) FROM review_steps WHERE request_id=?",id));
    }

    @Test void missingDirectFounderNeverFallsBackToOtherFounder() throws Exception {
        user(company,department,"","FOUNDER",false);
        String id=founderRequest(director,"无直属上级");
        assertNull(pendingReviewer(id)); decide(403,id,founder); decide(403,id,admin);
        assertEquals("PENDING",call(200,"GET","/reviews/"+id,director,null).get("status").asText());
        assertFalse(applied("无直属上级"));
    }

    @Test void disabledDirectManagerLeavesRequestPendingAndAdminCannotDecide() throws Exception {
        db.update("UPDATE users SET dispatch_enabled=true WHERE id=?", leader);
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)", employee, leader, company);
        var actor = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", employee));
        String id = (String) reviews.create(actor, "TASK", cn.workpanel.Db.id(), 1, Map.of(), Map.of("title", "直属失效"), "测试").get("id");
        assertEquals(leader, pendingReviewer(id));
        approve(revision(leader, Map.of("status", "DISABLED")).get("id").asText(), admin);
        assertNull(pendingReviewer(id));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND recipient_id=? AND type='REVIEW_UNASSIGNED'", id, employee));
        assertFalse(call(200, "GET", "/reviews/" + id, employee, null).get("reviewer_configured").asBoolean());
        call(403, "POST", "/reviews/" + id + "/decision", admin, Map.of("approve", true, "expectedVersion", 1));
    }

    String directorDeletion(String title) throws Exception {
        String task=cn.workpanel.Db.id();
        db.update("UPDATE users SET dispatch_enabled=true WHERE id=?",director);
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES (?,?,?,?,?,now()+interval '1 day','{}')",task,company,director,director,title);
        db.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?)",task,director,company);
        return call(200,"POST","/tasks/"+task+"/deletions",director,Map.of("version",1,"reason","直属删除审核")).get("id").asText();
    }

    int send(String who, String path, Map<String, Object> body) throws Exception {
        var request = java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:" + port + "/api" + path))
            .header("Authorization", "Bearer " + tokens.get(who)).header("Content-Type", "application/json")
            .POST(java.net.http.HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build();
        return http.send(request, java.net.http.HttpResponse.BodyHandlers.ofString()).statusCode();
    }
}
