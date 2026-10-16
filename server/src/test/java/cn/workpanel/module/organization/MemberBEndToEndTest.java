package cn.workpanel.module.organization;

import cn.workpanel.Db;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import static org.junit.jupiter.api.Assertions.*;

/** 一次真实 HTTP 链路：注册→登录→独立归属确认→候选组织修改→审核生效。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class MemberBEndToEndTest extends MemberBHttpSupport {
    @Autowired BCryptPasswordEncoder encoder;
    static final String PASSWORD = "End-to-end-password-2026";
    java.util.List<String> previousReviewers;
    @BeforeEach @Override public void fixture() {
        company = "default"; department = "product"; otherDepartment = "engineering";
        // 注册固定进入默认公司，临时隔离其他测试的审核人，结束后恢复其职责。
        previousReviewers = db.rows("SELECT id FROM users WHERE company_id=? AND company_reviewer=true", company).stream().map(row -> Db.str(row,"id")).toList();
        db.update("UPDATE users SET company_reviewer=false WHERE company_id=? AND company_reviewer=true", company);
        admin = user(company, department, "", "ADMIN", true);
        db.update("UPDATE users SET password_hash=?,must_change_password=true,department_id=NULL WHERE id=?", encoder.encode("Initial-test-password-2026"), admin);
        reviewer = user(company, department, "", "ADMIN", true);
        db.update("UPDATE users SET password_hash=? WHERE id=?", encoder.encode(PASSWORD), reviewer);
    }
    @AfterEach void restoreReviewers() {
        db.update("UPDATE users SET company_reviewer=false WHERE id IN (?,?)", admin, reviewer);
        if (previousReviewers != null) for (String id : previousReviewers) db.update("UPDATE users SET company_reviewer=true WHERE id=?", id);
    }
    @Test void registerLoginConfirmAndApproveOrganizationChangeWithRealSessions() throws Exception {
        String adminAccount = Db.str(db.one("SELECT account FROM users WHERE id=?", admin), "account");
        var adminLogin = call(200, "POST", "/auth/login", admin, Map.of("account", adminAccount, "password", "Initial-test-password-2026"));
        tokens.put(admin, adminLogin.get("token").asText());
        call(403, "GET", "/organization", admin, null);
        call(200, "POST", "/auth/password", admin, Map.of("oldPassword", "Initial-test-password-2026", "newPassword", PASSWORD));
        tokens.put(admin, call(200, "POST", "/auth/login", admin, Map.of("account", adminAccount, "password", PASSWORD)).get("token").asText());
        var reviewerAccount = db.one("SELECT account FROM users WHERE id=?", reviewer).get("account");
        tokens.put(reviewer, call(200, "POST", "/auth/login", reviewer, Map.of("account", reviewerAccount, "password", PASSWORD)).get("token").asText());
        String account = "e2e-" + UUID.randomUUID().toString().substring(0, 12);
        var registration = call(200, "POST", "/auth/register", admin, Map.of("account", account, "password", PASSWORD, "phone", "134" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000)), "name", "完整链路员工", "departmentId", department));
        employee = registration.get("id").asText();
        tokens.put(employee, call(200, "POST", "/auth/login", employee, Map.of("account", account, "password", PASSWORD)).get("token").asText());
        call(403, "GET", "/organization", employee, null);
        call(403, "POST", "/reviews/" + registration.get("reviewId").asText() + "/decision", employee, Map.of("approve", true));
        approve(registration.get("reviewId").asText(), employee);
        call(200, "GET", "/organization", employee, null);
        String revision = revision(employee, Map.of("departmentId", otherDepartment)).get("id").asText();
        assertEquals(department, call(200, "GET", "/auth/me", employee, null).get("department_id").asText());
        call(403, "POST", "/reviews/" + revision + "/decision", admin, Map.of("approve", true));
        approve(revision, admin);
        assertEquals(otherDepartment, call(200, "GET", "/auth/me", employee, null).get("department_id").asText());
        assertEquals(3, db.count("SELECT version FROM users WHERE id=?", employee));
        // 归属确认和随后调岗各应用一次，均需保留审计。
        assertEquals(2, db.count("SELECT count(*) FROM audit_records WHERE type='REVISION_APPLIED' AND object_id=?", employee));
        call(200, "POST", "/auth/logout", employee, null);
        call(401, "GET", "/auth/me", employee, null);
    }
}
