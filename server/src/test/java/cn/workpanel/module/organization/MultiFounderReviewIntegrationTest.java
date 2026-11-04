package cn.workpanel.module.organization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 多创始人互审：路由、自审、审核人更换、并发、失效改派与无审核人提醒。夹具与组织验收共用。 */
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

    @Test void peerFounderReviewsAndSelfReviewIsRejected() throws Exception {
        String peer = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "互审通过");
        var detail = call(200, "GET", "/reviews/" + id, founder, null);
        assertEquals("FOUNDER_PEER", detail.get("approval_mode").asText());
        assertTrue(detail.get("reviewer_selectable").asBoolean());
        assertEquals(peer, detail.get("reviewer_id").asText());
        assertFalse(applied("互审通过"));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND recipient_id=? AND type='REVIEW_PENDING'", id, peer));

        assertEquals("SELF_REVIEW", decide(403, id, founder).get("code").asText());
        decide(403, id, admin);
        var result = decide(200, id, peer);
        assertEquals("APPROVED", result.get("status").asText()); assertEquals("FOUNDER_PEER", result.get("decision_source").asText());
        assertTrue(applied("互审通过"));
        assertFalse(result.get("reviewer_selectable").asBoolean());
    }

    @Test void applicantChangesReviewerAndInvalidSelectionsAreRejected() throws Exception {
        String second = user(company, department, "", "FOUNDER", false), third = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "更换审核人");
        String first = pendingReviewer(id), other = first.equals(second) ? third : second;
        var candidates = call(200, "GET", "/reviews/" + id + "/reviewer-candidates", founder, null).get("items");
        assertEquals(2, candidates.size());
        for (var item : candidates) { assertNotEquals(founder, item.get("id").asText()); assertEquals(item.get("id").asText().equals(first), item.get("current").asBoolean()); }
        call(403, "GET", "/reviews/" + id + "/reviewer-candidates", first, null);

        for (String invalid : List.of(founder, admin, foreign, "missing"))
            assertEquals("INVALID_REVIEWER", call(400, "POST", "/reviews/" + id + "/reviewer", founder, Map.of("reviewerId", invalid, "expectedVersion", expected(id))).get("code").asText());
        call(409, "POST", "/reviews/" + id + "/reviewer", founder, Map.of("reviewerId", other, "expectedVersion", expected(id) + 1));
        call(403, "POST", "/reviews/" + id + "/reviewer", other, Map.of("reviewerId", other, "expectedVersion", expected(id)));

        call(200, "POST", "/reviews/" + id + "/reviewer", founder, Map.of("reviewerId", other, "expectedVersion", expected(id)));
        assertEquals(other, pendingReviewer(id));
        long steps = db.count("SELECT count(*) FROM review_steps WHERE request_id=?", id);
        call(200, "POST", "/reviews/" + id + "/reviewer", founder, Map.of("reviewerId", other, "expectedVersion", expected(id)));
        assertEquals(steps, db.count("SELECT count(*) FROM review_steps WHERE request_id=?", id));
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_REVIEWER_CHANGED'", id));

        decide(403, id, first);
        call(403, "GET", "/reviews/" + id, first, null);
        decide(200, id, other);
        assertTrue(applied("更换审核人"));
    }

    @Test void selectionUnsupportedOutsideFounderPeerMode() throws Exception {
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)", employee, leader, company);
        var body = new LinkedHashMap<String, Object>(Map.of("name", "直属审核", "version", 1, "reason", "测试"));
        String id = call(200, "POST", "/organization/users/" + colleague + "/revisions", admin, body).get("id").asText();
        assertFalse(call(200, "GET", "/reviews/" + id, admin, null).get("reviewer_selectable").asBoolean());
        assertEquals("REVIEWER_SELECTION_UNSUPPORTED", call(409, "GET", "/reviews/" + id + "/reviewer-candidates", admin, null).get("code").asText());
        assertEquals("REVIEWER_SELECTION_UNSUPPORTED", call(409, "POST", "/reviews/" + id + "/reviewer", admin, Map.of("reviewerId", reviewer, "expectedVersion", expected(id))).get("code").asText());
    }

    @Test void parallelApproveAndReselectOnlyOneWins() throws Exception {
        String second = user(company, department, "", "FOUNDER", false), third = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "并发互审");
        String current = pendingReviewer(id), other = current.equals(second) ? third : second;
        int version = expected(id);
        try (var pool = Executors.newFixedThreadPool(2)) {
            var approve = pool.submit(() -> send(current, "/reviews/" + id + "/decision", Map.of("approve", true, "expectedVersion", version)));
            var reselect = pool.submit(() -> send(founder, "/reviews/" + id + "/reviewer", Map.of("reviewerId", other, "expectedVersion", version)));
            int a = approve.get(20, TimeUnit.SECONDS), b = reselect.get(20, TimeUnit.SECONDS);
            assertTrue(a == 200 && b == 409 || a == 403 && b == 200, a + "/" + b);
        }
        assertEquals(1, db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state='PENDING'", id) + db.count("SELECT count(*) FROM review_requests WHERE id=? AND status='APPROVED'", id));
        assertTrue(db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND title='并发互审'", company) <= 1);
    }

    @Test void duplicateParallelApprovalAppliesOnce() throws Exception {
        String peer = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "重复批准");
        int version = expected(id);
        try (var pool = Executors.newFixedThreadPool(2)) {
            var one = pool.submit(() -> send(peer, "/reviews/" + id + "/decision", Map.of("approve", true, "expectedVersion", version)));
            var two = pool.submit(() -> send(peer, "/reviews/" + id + "/decision", Map.of("approve", true, "expectedVersion", version)));
            assertEquals(Set.of(200, 409), Set.of(one.get(20, TimeUnit.SECONDS), two.get(20, TimeUnit.SECONDS)));
        }
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_APPROVED'", id));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'", id));
    }

    @Test void disablingReviewerFounderReroutesAndLastFounderStaysPending() throws Exception {
        String second = user(company, department, "", "FOUNDER", false), third = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "停用改派");
        String first = pendingReviewer(id), other = first.equals(second) ? third : second;

        approve(revision(first, Map.of("status", "DISABLED")).get("id").asText(), admin);
        assertEquals(other, pendingReviewer(id));
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_AUTO_REROUTED'", id));
        assertTrue(db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND recipient_id=? AND type='REVIEW_PENDING'", id, other) >= 1);

        approve(revision(other, Map.of("status", "DISABLED")).get("id").asText(), admin);
        assertNull(pendingReviewer(id));
        assertEquals("PENDING", db.one("SELECT status FROM review_requests WHERE id=?", id).get("status"));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND recipient_id=? AND type='REVIEW_UNASSIGNED'", id, founder));
        assertTrue(db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND recipient_id=? AND type='REVIEW_UNASSIGNED'", id, admin) >= 1);
        decide(403, id, admin);
        assertFalse(applied("停用改派"));

        // 仅剩一位创始人：申请人显式 reroute 后按权限与版本免审。
        var result = call(200, "POST", "/reviews/" + id + "/reroute", founder, Map.of());
        assertEquals("APPROVED", result.get("status").asText()); assertEquals("FOUNDER_EXEMPT", result.get("decision_source").asText());
        assertTrue(applied("停用改派"));
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

    @Test void failedOrganizationChangeDoesNotReroute() throws Exception {
        String second = user(company, department, "", "FOUNDER", false);
        String id = founderRequest(founder, "冲突不改派");
        String review = revision(second, Map.of("status", "DISABLED")).get("id").asText();
        db.update("UPDATE users SET version=version+1 WHERE id=?", second);
        var detail = call(200, "GET", "/reviews/" + review, admin, null);
        for (var step : detail.get("steps")) if (step.get("state").asText().equals("PENDING"))
            call(409, "POST", "/reviews/" + review + "/decision", step.get("reviewer_id").asText(), Map.of("approve", true, "expectedVersion", detail.get("expected_version").asInt()));
        assertEquals(second, pendingReviewer(id));
        assertEquals(0, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_AUTO_REROUTED'", id));
    }

    int send(String who, String path, Map<String, Object> body) throws Exception {
        var request = java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:" + port + "/api" + path))
            .header("Authorization", "Bearer " + tokens.get(who)).header("Content-Type", "application/json")
            .POST(java.net.http.HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build();
        return http.send(request, java.net.http.HttpResponse.BodyHandlers.ofString()).statusCode();
    }
}
