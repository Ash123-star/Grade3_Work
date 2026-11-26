package cn.workpanel.module.commerce;

import cn.workpanel.Db;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
        "app.admin-phone=13900000001", "app.deepseek-key=local-mock-only", "app.jobs-enabled=false"
})
class CommerceIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired ObjectMapper json;
    private final HttpClient http = HttpClient.newHttpClient();
    private String company;
    private String otherCompany;
    private String admin;
    private String otherAdmin;
    private String employee;
    private String pending;
    private String initialPassword;

    private static final String ORDERED = "2026-11-24T00:00:00+08:00";
    private static final String UPDATED = "2026-11-24T01:00:00+08:00";

    @BeforeEach
    void fixtures() {
        company = tenant();
        otherCompany = tenant();
        admin = user(company, "ADMIN", "ACTIVE", false);
        otherAdmin = user(otherCompany, "ADMIN", "ACTIVE", false);
        employee = user(company, "EMPLOYEE", "ACTIVE", false);
        pending = user(company, "EMPLOYEE", "PENDING", false);
        initialPassword = user(company, "ADMIN", "ACTIVE", true);
    }

    @Test
    void importsThenReconcilesOverviewDetailsAndCustomerBinding() throws Exception {
        var file = Map.of("members", List.of(member("m-1")), "orders", List.of(
                order("order-a", "m-1", "PAID", "CNY", "0.10", ORDERED, UPDATED),
                order("order-b", null, "PAID", "CNY", "0.20", ORDERED, UPDATED),
                order("order-c", "m-1", "REFUNDED", "USD", "4", ORDERED, UPDATED),
                order("order-outside", null, "PAID", "CNY", "900", "2026-11-24T16:00:00Z", "2026-11-24T16:00:00Z")));
        var receipt = upload(200, admin, json.writeValueAsString(file));
        assertEquals(1, receipt.path("members").path("applied").asInt());
        assertEquals(4, receipt.path("orders").path("applied").asInt());
        assertFalse(receipt.path("replayed").asBoolean());
        assertTrue(receipt.path("sha256").asText().matches("[0-9a-f]{64}"));

        String day = "from=2026-11-24&to=2026-11-24";
        var overview = get(200, "/commerce/overview?" + day, admin);
        assertEquals(3, overview.path("orderCount").asInt());
        var paid = overview.path("groups").get(0);
        assertEquals("PAID", paid.path("status").asText());
        assertEquals("CNY", paid.path("currency").asText());
        assertEquals("0.3000", paid.path("amount").asText());
        assertEquals("4.0000", overview.path("groups").get(1).path("amount").asText());

        String drill = "/commerce/orders?" + day + "&status=PAID&currency=CNY&limit=1";
        var firstPage = get(200, drill, admin);
        var secondPage = get(200, drill + "&cursor=" + firstPage.path("nextCursor").asText(), admin);
        assertEquals(2, firstPage.path("total").asInt());
        var first = firstPage.path("items").get(0);
        var second = secondPage.path("items").get(0);
        assertEquals("order-a", first.path("externalOrderId").asText());
        assertEquals("order-b", second.path("externalOrderId").asText());
        assertEquals(new BigDecimal(paid.path("amount").asText()),
                new BigDecimal(first.path("amount").asText()).add(new BigDecimal(second.path("amount").asText())));
        assertEquals(receipt.path("id"), first.path("importId"));
        assertEquals(1, first.path("sourceRow").asInt());
        assertTrue(secondPage.path("nextCursor").isNull());
        var source = get(200, "/commerce/imports/" + first.path("importId").asText(), admin);
        assertEquals(receipt.path("sha256"), source.path("sha256"));

        String customer = createCustomer(admin);
        String filter = "customerId=" + customer;
        assertEquals(0, get(200, "/commerce/orders?" + filter, admin).path("total").asInt());
        assertEquals(0, get(200, "/commerce/overview?" + filter, admin).path("orderCount").asInt());
        assertEquals(0, get(200, "/commerce/members?" + filter, admin).path("total").asInt());

        call(200, "PUT", "/customers/" + customer + "/membership", admin, Map.of("mallMemberId", "m-1", "version", 0));
        var importedMember = get(200, "/commerce/members?" + filter, admin).path("items").get(0);
        assertEquals("m-1", importedMember.path("externalMemberId").asText());
        assertEquals(2, get(200, "/commerce/overview?" + filter, admin).path("orderCount").asInt());
        assertEquals(2, get(200, "/commerce/orders?" + filter, admin).path("total").asInt());

        call(200, "PUT", "/customers/" + customer + "/membership", admin, Map.of("mallMemberId", "not-imported", "version", 1));
        assertEquals(0, get(200, "/commerce/orders?" + filter, admin).path("total").asInt());
        assertEquals(0, get(200, "/commerce/members?" + filter, admin).path("total").asInt());
    }

    @Test
    void identicalConcurrentUploadsReuseReceiptAndAudit() throws Exception {
        String data = file(order("repeat", null, "PAID", "CNY", "139.50", ORDERED, UPDATED));
        var firstAttempt = http.sendAsync(uploadRequest(admin, data), HttpResponse.BodyHandlers.ofString());
        var secondAttempt = http.sendAsync(uploadRequest(admin, data), HttpResponse.BodyHandlers.ofString());
        var first = decode(200, firstAttempt.get(20, TimeUnit.SECONDS));
        var second = decode(200, secondAttempt.get(20, TimeUnit.SECONDS));
        assertEquals(first.path("id"), second.path("id"));
        assertNotEquals(first.path("replayed"), second.path("replayed"));
        assertEquals(1, db.count("SELECT count(*) FROM commerce_imports WHERE company_id=?", company));
        assertEquals(1, db.count("SELECT count(*) FROM audit_records WHERE company_id=? AND type='COMMERCE_IMPORTED'", company));
        assertEquals(1, get(200, "/commerce/overview", admin).path("orderCount").asInt());
        var equivalent = upload(200, admin, "\n" + data);
        assertEquals(1, equivalent.path("orders").path("unchanged").asInt());
        assertEquals(1, get(200, "/commerce/overview", admin).path("orderCount").asInt());
    }

    @Test
    void newerSnapshotsApplyOldSnapshotsDoNotAndConflictsRollBack() throws Exception {
        upload(200, admin, file(order("revision", null, "PAID", "CNY", "15", ORDERED, UPDATED)));
        String newer = "2026-11-24T02:00:00+08:00";
        var fresh = upload(200, admin, file(order("revision", null, "REFUNDED", "CNY", "15", ORDERED, newer)));
        var old = upload(200, admin, file(order("revision", null, "PAID", "CNY", "15", ORDERED, ORDERED)));
        assertEquals(1, old.path("orders").path("stale").asInt());

        var outcome = upload(409, admin, json.writeValueAsString(Map.of(
                "members", List.of(member("new-member")), "orders", List.of(
                        order("new-order", "new-member", "PAID", "CNY", "1", ORDERED, UPDATED),
                        order("revision", null, "PAID", "CNY", "15", ORDERED, newer)))));
        assertEquals("COMMERCE_SNAPSHOT_CONFLICT", outcome.path("code").asText());
        assertEquals("orders", outcome.path("section").asText());
        assertEquals(2, outcome.path("row").asInt());
        assertEquals("sourceUpdatedAt", outcome.path("field").asText());
        assertEquals(0, get(200, "/commerce/members", admin).path("total").asInt());
        assertEquals(3, db.count("SELECT count(*) FROM commerce_imports WHERE company_id=?", company));

        var identityChange = upload(409, admin, file(order("revision", null, "REFUNDED", "USD", "15", ORDERED,
                "2026-11-24T03:00:00+08:00")));
        assertEquals("currency", identityChange.path("field").asText());
        var summary = get(200, "/commerce/overview", admin);
        assertEquals(1, summary.path("orderCount").asInt());
        assertEquals("REFUNDED", summary.path("groups").get(0).path("status").asText());
        assertEquals(fresh.path("id"), get(200, "/commerce/orders", admin).path("items").get(0).path("importId"));
    }

    @Test
    void rejectsForeignMemberAndInvalidFileWithLocationAndNoRows() throws Exception {
        upload(200, otherAdmin, json.writeValueAsString(Map.of("members", List.of(member("foreign-member")))));
        var missing = upload(400, admin, file(order("bad", "foreign-member", "PAID", "CNY", "1", ORDERED, UPDATED)));
        assertEquals("orders", missing.path("section").asText());
        assertEquals(1, missing.path("row").asInt());
        assertEquals("externalMemberId", missing.path("field").asText());
        assertFalse(missing.toString().contains("foreign-member"));
        assertFalse(missing.path("traceId").asText().isBlank());
        assertEquals(0, db.count("SELECT count(*) FROM commerce_imports WHERE company_id=?", company));

        assertEquals("file", upload(400, admin, "{}").path("section").asText());
        assertEquals("COMMERCE_FILE_TOO_LARGE", upload(413, admin, " ".repeat(1024 * 1024 + 1)).path("code").asText());
        assertEquals(0, get(200, "/commerce/orders", admin).path("total").asInt());
    }

    @Test
    void enforcesEveryCommerceEntryAndTenantScope() throws Exception {
        String data = file(order("same", null, "PAID", "CNY", "19.99", ORDERED, UPDATED));
        var imported = upload(200, admin, data);
        String batch = "/commerce/imports/" + imported.path("id").asText();
        for (var unauthorized : List.of(employee, pending, initialPassword)) {
            for (var path : List.of("/commerce/overview", "/commerce/orders", "/commerce/members", batch)) {
                get(403, path, unauthorized);
            }
            upload(403, unauthorized, data);
        }
        get(401, "/commerce/orders", null);
        get(404, batch, otherAdmin);
        assertEquals(0, get(200, "/commerce/overview", otherAdmin).path("orderCount").asInt());
        assertEquals(0, get(200, "/commerce/orders", otherAdmin).path("total").asInt());
        assertNotEquals(imported.path("id"), upload(200, otherAdmin, data).path("id"));
        assertEquals(1, get(200, "/commerce/overview", otherAdmin).path("orderCount").asInt());
        assertEquals(1, get(200, "/commerce/overview", admin).path("orderCount").asInt());

        String otherCustomer = createCustomer(otherAdmin);
        for (var path : List.of("/commerce/orders", "/commerce/overview", "/commerce/members")) {
            get(404, path + "?customerId=" + otherCustomer, admin);
            get(400, path + "?customerId=one&externalMemberId=two", admin);
        }
        get(400, "/commerce/overview?from=bad-date", admin);
        get(400, "/commerce/overview?from=2026-11-25&to=2026-11-24", admin);
        get(400, "/commerce/orders?status=BOGUS", admin);
        get(400, "/commerce/orders?limit=0", admin);

        db.update("UPDATE users SET role='EMPLOYEE' WHERE id=(SELECT user_id FROM sessions WHERE token_hash=?)", Db.hash(admin));
        get(403, "/commerce/overview", admin);
        get(403, "/commerce/orders", admin);
    }

    @Test
    void publishesCommerceOpenApi() throws Exception {
        var response = http.send(request("/openapi", null).GET().build(), HttpResponse.BodyHandlers.ofString());
        var openapi = decode(200, response);
        var paths = openapi.path("paths");
        var imports = paths.path("/api/commerce/imports").path("post");
        assertTrue(imports.path("requestBody").path("content").has("multipart/form-data"));
        assertTrue(imports.path("responses").path("409").toString().contains("ImportFailure"));
        for (String path : List.of("/overview", "/orders", "/members", "/imports/{id}")) {
            var success = paths.path("/api/commerce" + path).path("get").path("responses").path("200");
            assertTrue(success.path("content").path("application/json").has("schema"), path);
        }
        Files.writeString(Path.of("target", "commerce-openapi.json"), response.body(), StandardCharsets.UTF_8);
    }

    private String tenant() {
        String id = Db.id();
        db.update("INSERT INTO companies(id,name) VALUES (?,?)", id, "商城集成测试");
        return id;
    }

    private String user(String tenant, String role, String status, boolean mustChange) {
        String id = Db.id();
        String token = Db.id();
        db.update("""
                INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status,must_change_password)
                VALUES (?,?,?,'not-used-for-login','集成测试',?,?,?,?)
                """, id, tenant, "commerce-" + id, "test-" + id, role, status, mustChange);
        db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')", Db.hash(token), id);
        return token;
    }

    private String createCustomer(String who) throws Exception {
        return call(201, "POST", "/customers", who, Map.of("kind", "INDIVIDUAL", "name", "商城联调客户"))
                .path("id").asText();
    }

    private JsonNode get(int status, String path, String token) throws Exception {
        return call(status, "GET", path, token, null);
    }

    private JsonNode call(int status, String method, String path, String token, Object body) throws Exception {
        var request = request(path, token);
        if (body != null) request.header("Content-Type", "application/json");
        return decode(status, http.send(request.method(method, body == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString()));
    }

    private JsonNode upload(int status, String token, String body) throws Exception {
        return decode(status, http.send(uploadRequest(token, body), HttpResponse.BodyHandlers.ofString()));
    }

    private HttpRequest uploadRequest(String token, String body) {
        String boundary = "commerce-test-" + Db.id();
        String multipart = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"input.json\"\r\n"
                + "Content-Type: application/json\r\n\r\n" + body + "\r\n--" + boundary + "--\r\n";
        return request("/commerce/imports", token).header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofString(multipart)).build();
    }

    private HttpRequest.Builder request(String path, String token) {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api" + path))
                .timeout(Duration.ofSeconds(20));
        if (token != null) request.header("Authorization", "Bearer " + token);
        return request;
    }

    private JsonNode decode(int status, HttpResponse<String> response) throws Exception {
        assertEquals(status, response.statusCode(), response.request().uri() + " " + response.body());
        return json.readTree(response.body());
    }

    private String file(Map<String, Object> order) throws Exception {
        return json.writeValueAsString(Map.of("orders", List.of(order)));
    }

    private static Map<String, Object> member(String id) {
        return Map.of("externalMemberId", id, "status", "ACTIVE", "level", "金卡", "sourceUpdatedAt", UPDATED);
    }

    private static Map<String, Object> order(String id, String member, String status, String currency, String amount,
                                             String orderedAt, String updatedAt) {
        var fields = new java.util.LinkedHashMap<String, Object>();
        fields.put("externalOrderId", id);
        fields.put("externalMemberId", member);
        fields.put("status", status);
        fields.put("currency", currency);
        fields.put("amount", amount);
        fields.put("orderedAt", orderedAt);
        fields.put("sourceUpdatedAt", updatedAt);
        return fields;
    }
}
