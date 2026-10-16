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

abstract class MemberBHttpSupport {

    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired OrganizationValidation validation;
    @Autowired PlatformTransactionManager manager;
    static final ObjectMapper JSON = new ObjectMapper();
    final HttpClient http = HttpClient.newHttpClient();
    final Map<String, String> tokens = new HashMap<>();
    String company, department, otherDepartment, team, otherTeam, admin, reviewer, employee, colleague, leader, director, founder, outside, foreign;
    @BeforeEach public void fixture() {
        company = Db.id(); department = Db.id(); otherDepartment = Db.id(); team = Db.id(); otherTeam = Db.id();
        db.update("INSERT INTO companies(id,name) VALUES (?,?)", company, "组织测试");
        db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?),(?,?,?)", department, company, "本部门", otherDepartment, company, "其他部门");
        db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?),(?,?,?,?)", team, company, department, "本团队", otherTeam, company, otherDepartment, "其他团队");
        admin = user(company, department, "", "ADMIN", true); reviewer = user(company, department, "", "ADMIN", true);
        employee = user(company, department, team, "EMPLOYEE", false); colleague = user(company, department, team, "EMPLOYEE", false);
        leader = user(company, department, team, "LEADER", false); director = user(company, department, "", "DIRECTOR", false); founder = user(company, department, "", "FOUNDER", false);
        outside = user(company, otherDepartment, otherTeam, "EMPLOYEE", false);
        String foreignCompany = Db.id(), foreignDepartment = Db.id();
        db.update("INSERT INTO companies(id,name) VALUES (?,?)", foreignCompany, "范围外公司");
        db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)", foreignDepartment, foreignCompany, "范围外部门");
        foreign = user(foreignCompany, foreignDepartment, "", "EMPLOYEE", false);
    }
    String user(String company, String department, String team, String role, boolean reviewer) {
        String id = Db.id(), token = Db.id();
        String phone = "135" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000));
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,company_reviewer) VALUES (?,?,?,'not-used-for-login',?,?,?,?,?,'ACTIVE',?)", id, company, "org-" + id, phone, id, department, team.isEmpty() ? null : team, role, reviewer);
        db.update("INSERT INTO user_roles VALUES (?,?)", id, role);
        db.update("INSERT INTO sessions VALUES (?,?,?)", Db.hash(token), id, Timestamp.from(Instant.now().plusSeconds(3600)));
        tokens.put(id, token); return id;
    }
    public JsonNode call(int expected, String method, String path, String who, Object body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api" + path)).timeout(Duration.ofSeconds(20));
        builder.header("Authorization", "Bearer " + tokens.get(who));
        if (body != null) builder.header("Content-Type", "application/json");
        var response = http.send(builder.method(method, body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
        assertEquals(expected, response.statusCode(), path + " " + response.body());
        assertTrue(response.headers().firstValue("X-Trace-Id").isPresent()); return JSON.readTree(response.body());
    }
    public JsonNode revision(String target, Map<String, Object> changes) throws Exception {
        var body = new LinkedHashMap<>(changes); body.put("version", ((Number) db.one("SELECT version FROM users WHERE id=?", target).get("version")).intValue()); body.put("reason", "组织测试变更");
        return call(200, "POST", "/organization/users/" + target + "/revisions", admin, body);
    }
    public JsonNode approve(String id, String applicant) throws Exception {
        var detail = call(200, "GET", "/reviews/" + id, applicant, null); JsonNode result = detail;
        for (var step : detail.get("steps")) if (step.get("state").asText().equals("PENDING"))
            result = call(200, "POST", "/reviews/" + id + "/decision", step.get("reviewer_id").asText(), Map.of("approve", true, "reason", "独立复核"));
        assertEquals("APPROVED", result.get("status").asText()); return result;
    }
    Set<String> visible(String who) throws Exception {
        Set<String> result = new HashSet<>();
        for (var item : call(200, "GET", "/organization/people?limit=100", who, null).get("items")) {
            result.add(item.get("id").asText()); assertFalse(item.has("password_hash")); assertFalse(item.has("phone"));
        }
        return result;
    }

}
