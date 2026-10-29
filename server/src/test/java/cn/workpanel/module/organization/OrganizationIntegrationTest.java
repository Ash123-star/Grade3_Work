package cn.workpanel.module.organization;

import cn.workpanel.*;
import cn.workpanel.module.organization.application.OrganizationValidation;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.net.URI;
import java.net.http.*;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 独立公司夹具，不修改 E 的公共测试；真实 HTTP 与数据库验收。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
public class OrganizationIntegrationTest extends MemberBHttpSupport {
    @Test void fiveRolesAndCompanyDepartmentTeamScopes() throws Exception {
        for (String global : List.of(admin, founder)) { assertEquals(8, visible(global).size()); assertFalse(visible(global).contains(foreign)); }
        assertEquals(7, visible(director).size()); assertFalse(visible(director).contains(outside));
        assertEquals(Set.of(employee, colleague, leader), visible(leader)); assertEquals(Set.of(employee), visible(employee));
        call(403, "GET", "/organization/people?dispatch=true", employee, null);
        call(404, "POST", "/organization/users/" + foreign + "/revisions", admin, Map.of("version", 1, "reason", "跨公司", "name", "非法"));
        call(403, "GET", "/organization/audit", employee, null);
    }
    @Test void treeDoesNotTruncateAtOneHundredAndPaginationIsComplete() throws Exception {
        for (int i = 0; i < 105; i++) user(company, department, team, "EMPLOYEE", false);
        var tree = call(200, "GET", "/organization", admin, null).get("users");
        assertEquals(113, tree.get("total").asInt()); assertEquals(113, tree.get("items").size());
        Set<String> ids = new HashSet<>(); int cursor = 0;
        do {
            var page = call(200, "GET", "/organization/people?limit=30&cursor=" + cursor, admin, null);
            for (var item : page.get("items")) assertTrue(ids.add(item.get("id").asText()));
            if (page.get("items").isEmpty()) break;
            cursor = page.get("nextCursor").asInt();
        } while (cursor < 113);
        assertEquals(113, ids.size()); assertFalse(ids.contains(foreign));
    }
    @Test void invalidFieldsHierarchyAndReportingCycleDoNotCreateCandidates() throws Exception {
        for (var change : List.of(Map.of("role", "ROOT"), Map.of("role", "LEADER", "teamId", ""), Map.of("teamId", otherTeam), Map.of("managerId", employee), Map.of("dispatchEnabled", "true"))) {
            var body = new LinkedHashMap<String, Object>(change); body.put("version", 1); body.put("reason", "无效候选");
            int expected = change.containsKey("teamId") && change.get("teamId").equals(otherTeam) ? 404 : 400;
            call(expected, "POST", "/organization/users/" + employee + "/revisions", admin, body);
        }
        db.update("INSERT INTO reporting_relations VALUES (?,?,?)", colleague, employee, company);
        call(400, "POST", "/organization/users/" + employee + "/revisions", admin, Map.of("version", 1, "reason", "汇报环", "managerId", colleague));
        assertEquals(0, db.count("SELECT count(*) FROM review_requests WHERE company_id=?", company));
    }
    @Test void approvedRevisionChangesNextRequestScopeAndRejectedKeepsOldValues() throws Exception {
        String historicalLog = cn.workpanel.Db.id(), historicalTask = cn.workpanel.Db.id();
        db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body) VALUES (?,?,?,DATE '2026-01-01','{}')", historicalLog, company, employee);
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES (?,?,?,?,'历史任务',now()+interval '1 day','{}')", historicalTask, company, employee, admin);
        var request = revision(employee, Map.of("departmentId", otherDepartment, "teamId", otherTeam));
        assertEquals(department, db.one("SELECT department_id FROM users WHERE id=?", employee).get("department_id"));
        approve(request.get("id").asText(), admin);
        assertEquals(otherDepartment, call(200, "GET", "/auth/me", employee, null).get("department_id").asText());
        assertFalse(visible(leader).contains(employee));
        assertEquals(1, db.count("SELECT count(*) FROM daily_logs WHERE id=? AND owner_id=?", historicalLog, employee));
        assertEquals(1, db.count("SELECT count(*) FROM tasks WHERE id=? AND owner_id=?", historicalTask, employee));
        var rejected = revision(employee, Map.of("name", "不应生效"));
        var detail = call(200, "GET", "/reviews/" + rejected.get("id").asText(), admin, null);
        call(200, "POST", "/reviews/" + rejected.get("id").asText() + "/decision", detail.get("steps").get(0).get("reviewer_id").asText(), Map.of("approve", false, "reason", "不予通过", "expectedVersion", detail.get("expected_version").asInt()));
        assertEquals(employee, db.one("SELECT name FROM users WHERE id=?", employee).get("name"));
    }
    @Test void pendingAccountsAndInvalidPagingAreRejected() throws Exception {
        db.update("UPDATE users SET status='PENDING' WHERE id=?", employee);
        call(403, "GET", "/organization", employee, null);
        call(400, "GET", "/organization/people?limit=101", admin, null);
        call(400, "GET", "/organization/people?cursor=-1", admin, null);
    }
    @Test void membershipReviewerAndPolicyUseIndependentCandidates() throws Exception {
        db.update("UPDATE users SET status='PENDING' WHERE id=?", employee);
        var membership = call(200, "POST", "/organization/membership-application", employee, Map.of("version", 1, "reason", "确认归属", "departmentId", department));
        call(409, "POST", "/organization/membership-application", employee, Map.of("version", 1, "reason", "重复申请", "departmentId", department));
        approve(membership.get("id").asText(), employee);
        assertEquals("ACTIVE", call(200, "GET", "/auth/me", employee, null).get("status").asText());
        db.update("INSERT INTO reporting_relations VALUES (?,?,?)", employee, leader, company);
        var reviewerRequest = call(200, "POST", "/organization/reviewer-application", employee, Map.of("version", 2, "reason", "复核职责"));
        approve(reviewerRequest.get("id").asText(), employee);
        var user = call(200, "GET", "/auth/me", employee, null);
        assertEquals("EMPLOYEE", user.get("role").asText()); assertTrue(user.get("company_reviewer").asBoolean());
        var policy = call(200, "GET", "/organization/review-policy", admin, null);
        call(400, "POST", "/organization/review-policy/revisions", admin, Map.of("version", policy.get("version").asInt(), "reason", "退役多级策略", "taskTeamReview", false));
        var request = call(200, "POST", "/organization/review-policy/revisions", admin, Map.of("version", policy.get("version").asInt(), "reason", "授权策略审核", "aiWorkAuthorizationMaxDays", 15));
        assertFalse(policy.get("review_policy").has("taskTeamReview"));
        approve(request.get("id").asText(), admin);
        assertEquals(15, call(200, "GET", "/organization/review-policy", admin, null).at("/review_policy/aiWorkAuthorizationMaxDays").asInt());
    }
    @Test void departmentAndTeamCandidatesRemainInactiveUntilApproved() throws Exception {
        var request = call(200, "POST", "/organization/departments/revisions", admin, Map.of("version", 0, "reason", "新部门", "name", "新部门"));
        String id = request.get("target_id").asText();
        assertEquals(0, db.count("SELECT count(*) FROM departments WHERE id=?", id));
        approve(request.get("id").asText(), admin);
        var teamRequest = call(200, "POST", "/organization/teams/revisions", admin, Map.of("version", 0, "reason", "新团队", "name", "新团队", "departmentId", id));
        assertEquals(0, db.count("SELECT count(*) FROM teams WHERE id=?", teamRequest.get("target_id").asText()));
        approve(teamRequest.get("id").asText(), admin);
        assertEquals(id, db.one("SELECT department_id FROM teams WHERE id=?", teamRequest.get("target_id").asText()).get("department_id"));
    }
    @Test void lastAdministratorConstraintSerializesConcurrentChanges() throws Exception {
        var accepted = new java.util.concurrent.atomic.AtomicInteger();
        try (var pool = Executors.newFixedThreadPool(2)) {
            var futures = new ArrayList<Future<?>>();
            for (String id : List.of(admin, reviewer)) futures.add(pool.submit(() -> {
                try { new TransactionTemplate(manager).execute(status -> {
                    var row = db.one("SELECT * FROM users WHERE id=?", id);
                    var candidate = new HashMap<String, Object>(Map.of("name", row.get("name"), "role", "ADMIN", "status", "DISABLED", "departmentId", department, "teamId", "", "managerId", "", "dispatchEnabled", true, "companyReviewer", true));
                    validation.user(company, id, candidate);
                    db.update("UPDATE users SET status='DISABLED' WHERE id=?", id); accepted.incrementAndGet(); return null;
                }); } catch (ApiError error) { assertEquals("不能停用或降级最后一个管理员", error.getMessage()); }
            }));
            for (var future : futures) future.get(20, TimeUnit.SECONDS);
        }
        assertEquals(1, accepted.get()); assertEquals(1, db.count("SELECT count(*) FROM users WHERE company_id=? AND role='ADMIN' AND status='ACTIVE'", company));
    }
}
