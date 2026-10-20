package cn.workpanel.module.organization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 与组织验收共用独立公司夹具，验证审核层级、权限、并发、审计和原子回滚。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class ReviewIntegrationTest extends MemberBHttpSupport {
    @org.springframework.beans.factory.annotation.Autowired cn.workpanel.module.review.application.ReviewApplicationService reviews;
    JsonNode application(String applicant, String target, Map<String, Object> changes) throws Exception {
        var body = new LinkedHashMap<>(changes); body.put("version", 1); body.put("reason", "审核测试");
        return call(200, "POST", "/organization/users/" + target + "/revisions", applicant, body);
    }
    String firstReviewer(String request, String applicant) throws Exception { return call(200, "GET", "/reviews/" + request, applicant, null).get("steps").get(0).get("reviewer_id").asText(); }
    @Test void scopeSelfReviewInvalidDecisionAndRejectionAreEnforced() throws Exception {
        var request = application(admin, employee, Map.of("name", "候选值")); String id = request.get("id").asText();
        call(403, "POST", "/reviews/" + id + "/decision", admin, Map.of("approve", true));
        call(403, "GET", "/reviews/" + id, outside, null);
        assertEquals(0, call(200, "GET", "/reviews", outside, null).get("total").asInt());
        String current = firstReviewer(id, admin);
        call(400, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", "yes"));
        call(400, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", false, "reason", " \t"));
        call(400, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", false, "reason", 42));
        call(403, "POST", "/reviews/" + id + "/decision", outside, Map.of("approve", true));
        call(200, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", false, "reason", "驳回"));
        call(409, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", true));
        assertEquals(employee, db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_REJECTED'", id));
    }
    @Test void missingIndependentCompanyReviewerKeepsOldValueAndReroutes() throws Exception {
        db.update("UPDATE users SET company_reviewer=false WHERE id=?", reviewer);
        var request = application(admin, employee, Map.of("name", "待审内容")); String id = request.get("id").asText();
        assertTrue(call(200, "GET", "/reviews/" + id, admin, null).get("steps").isEmpty());
        assertEquals(employee, db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
        db.update("UPDATE users SET company_reviewer=true WHERE id=?", reviewer);
        call(200, "POST", "/reviews/" + id + "/reroute", admin, Map.of()); approve(id, admin);
        assertEquals("待审内容", db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
    }
    @Test void teamDepartmentCompanyLevelsOnlyApplyAfterLastStep() throws Exception {
        db.update("UPDATE users SET role='ADMIN' WHERE id=?", employee);
        var request = application(employee, colleague, Map.of("name", "三级审核")); String id = request.get("id").asText();
        var steps = call(200, "GET", "/reviews/" + id, employee, null).get("steps");
        assertEquals(3, steps.size()); assertEquals(leader, steps.get(0).get("reviewer_id").asText()); assertEquals(director, steps.get(1).get("reviewer_id").asText());
        call(403, "POST", "/reviews/" + id + "/decision", director, Map.of("approve", true));
        for (int i = 0; i < steps.size(); i++) {
            call(200, "POST", "/reviews/" + id + "/decision", steps.get(i).get("reviewer_id").asText(), Map.of("approve", true));
            assertEquals(i == steps.size() - 1 ? "三级审核" : colleague, db.one("SELECT name FROM users WHERE id=?", colleague).get("name"));
        }
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVISION_APPLIED'", colleague));
        assertEquals(3, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'", id));
    }
    @Test void versionConflictRollsBackFinalDecisionAndRetainsPriorVersion() throws Exception {
        String first = application(admin, employee, Map.of("name", "第一版本")).get("id").asText();
        String second = application(admin, employee, Map.of("name", "冲突版本")).get("id").asText();
        approve(first, admin);
        var detail = call(200, "GET", "/reviews/" + second, admin, null); var steps = detail.get("steps");
        for (int i = 0; i < steps.size() - 1; i++) call(200, "POST", "/reviews/" + second + "/decision", steps.get(i).get("reviewer_id").asText(), Map.of("approve", true));
        call(409, "POST", "/reviews/" + second + "/decision", steps.get(steps.size() - 1).get("reviewer_id").asText(), Map.of("approve", true));
        assertEquals("第一版本", db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
        assertEquals("PENDING", db.one("SELECT state FROM review_steps WHERE request_id=? ORDER BY position DESC LIMIT 1", second).get("state"));
        assertEquals(steps.size() - 1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVIEW_APPROVED'", second));
    }
    @Test void duplicateParallelDecisionOnlyWritesOnce() throws Exception {
        // 去掉中间层，只验证同一最终步骤的并发事务，业务模型不被修改。
        db.update("UPDATE users SET department_id=NULL WHERE id=?", admin);
        String id = application(admin, employee, Map.of("name", "并发审核")).get("id").asText();
        String current = firstReviewer(id, admin);
        try (var pool = Executors.newFixedThreadPool(2)) {
            var results = new ArrayList<Future<Integer>>();
            for (int i = 0; i < 2; i++) results.add(pool.submit(() -> {
                var builder = java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:" + port + "/api/reviews/" + id + "/decision"))
                    .header("Authorization", "Bearer " + tokens.get(current)).header("Content-Type", "application/json").POST(java.net.http.HttpRequest.BodyPublishers.ofString("{\"approve\":true}"));
                return http.send(builder.build(), java.net.http.HttpResponse.BodyHandlers.ofString()).statusCode();
            }));
            var statuses = new HashSet<Integer>(); for (var result : results) statuses.add(result.get(20, TimeUnit.SECONDS));
            assertEquals(Set.of(200, 409), statuses);
        }
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='REVISION_APPLIED'", employee));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'", id));
    }
    @Test void organizationChangedDuringReviewIsRevalidatedAndRolledBack() throws Exception {
        String id = application(admin, employee, Map.of("teamId", otherTeam, "departmentId", otherDepartment)).get("id").asText();
        db.update("UPDATE users SET team_id=NULL WHERE team_id=?", otherTeam);
        db.update("UPDATE teams SET department_id=? WHERE id=?", department, otherTeam);
        var steps = call(200, "GET", "/reviews/" + id, admin, null).get("steps");
        for (int i = 0; i < steps.size() - 1; i++) call(200, "POST", "/reviews/" + id + "/decision", steps.get(i).get("reviewer_id").asText(), Map.of("approve", true));
        call(404, "POST", "/reviews/" + id + "/decision", steps.get(steps.size() - 1).get("reviewer_id").asText(), Map.of("approve", true));
        assertEquals(team, db.one("SELECT team_id FROM users WHERE id=?", employee).get("team_id"));
        assertEquals("PENDING", db.one("SELECT status FROM review_requests WHERE id=?", id).get("status"));
    }
    @Test void taskPolicyCanSkipIntermediateLevelsButKeepsIndependentCompanyReviewer() throws Exception {
        String applicant = user(company, department, team, "ADMIN", false);
        var actor = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", applicant));
        for (int levels = 3; levels >= 1; levels--) {
            db.update("UPDATE companies SET review_policy=?::jsonb WHERE id=?", JSON.writeValueAsString(Map.of("taskTeamReview", levels == 3, "taskDepartmentReview", levels >= 2)), company);
            var request = reviews.create(actor, "TASK", cn.workpanel.Db.id(), 1, Map.of(), Map.of("title", "路由测试"), "测试审核策略路由");
            var steps = call(200, "GET", "/reviews/" + request.get("id"), applicant, null).get("steps");
            assertEquals(levels, steps.size());
            String last = steps.get(steps.size() - 1).get("reviewer_id").asText();
            assertNotEquals(applicant, last);
            assertEquals(true, db.one("SELECT company_reviewer FROM users WHERE id=?", last).get("company_reviewer"));
        }
    }
    @Test void revokedReviewerCannotUseStaleApplicationIdentity() throws Exception {
        String id = application(admin, employee, Map.of("name", "资格已撤销")).get("id").asText();
        String current = firstReviewer(id, admin);
        var staleActor = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", current));
        db.update("UPDATE users SET role='EMPLOYEE',company_reviewer=false WHERE id=?", current);
        assertThrows(cn.workpanel.ApiError.class, () -> reviews.decide(staleActor, id, true, "旧身份尝试"));
        assertEquals("PENDING", db.one("SELECT state FROM review_steps WHERE request_id=? ORDER BY position LIMIT 1", id).get("state"));
        assertEquals(employee, db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
    }

    @Test void logModuleWriteFailureRollsBackBusinessDecisionAuditAndOutbox() throws Exception {
        // 在业务 UPDATE 之后制造真实的历史版本唯一键冲突，验证跨模块事务而非仅输入校验。
        db.update("UPDATE users SET department_id=NULL WHERE id=?", admin);
        String log = cn.workpanel.Db.id();
        var before = Map.<String,Object>of("work", "原日报");
        var candidate = Map.<String,Object>of("work", "候选日报");
        db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES (?,?,?,CURRENT_DATE,?::jsonb,true,now())", log, company, admin, db.write(before));
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,2,?::jsonb)", company, log, db.write(before));
        var actor = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", admin));
        String id = (String) reviews.create(actor, "LOG", log, 1, before, candidate, "验证业务失败回滚").get("id");
        String current = firstReviewer(id, admin);
        var approver = cn.workpanel.Actor.from(db.one("SELECT * FROM users WHERE id=?", current));
        assertThrows(org.springframework.dao.DataIntegrityViolationException.class, () -> reviews.decide(approver, id, true, "同意"));
        assertEquals(before, db.read(db.one("SELECT body FROM daily_logs WHERE id=?", log).get("body")));
        assertEquals(1, db.count("SELECT version FROM daily_logs WHERE id=?", log));
        assertEquals("PENDING", db.one("SELECT status FROM review_requests WHERE id=?", id).get("status"));
        assertEquals("PENDING", db.one("SELECT state FROM review_steps WHERE request_id=?", id).get("state"));
        assertEquals(0, db.count("SELECT count(*) FROM audit_records WHERE object_id IN (?,?) AND type IN ('REVISION_APPLIED','REVIEW_APPROVED')", log, id));
        assertEquals(0, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'", id));
        // 清除故障后同一个申请可以成功一次；重复决定不能再次写入。
        db.update("DELETE FROM log_versions WHERE log_id=? AND version=2", log);
        approve(id, admin);
        assertEquals(candidate, db.read(db.one("SELECT body FROM daily_logs WHERE id=?", log).get("body")));
        call(409, "POST", "/reviews/" + id + "/decision", current, Map.of("approve", true));
        assertEquals(1, db.count("SELECT count(*) FROM log_versions WHERE log_id=? AND version=2", log));
        assertEquals(1, db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='REVIEW_APPROVED'", id));
    }
}
