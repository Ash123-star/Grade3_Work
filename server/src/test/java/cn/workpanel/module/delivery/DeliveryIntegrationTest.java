package cn.workpanel.module.delivery;

import cn.workpanel.Db;
import com.fasterxml.jackson.databind.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import java.net.URI;
import java.net.http.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
        "app.admin-phone=13900000001", "app.deepseek-key=local-mock-only", "app.jobs-enabled=false"
})
class DeliveryIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired ObjectMapper json;
    final HttpClient http = HttpClient.newHttpClient();
    final String company = "delivery-" + UUID.randomUUID(), other = "other-" + company;
    final Map<String, String> tokens = new HashMap<>();
    static final String DELIVERIES = "/offline-deliveries";

    String uid(String who) { return (who.equals("outsider") ? other : company) + "-" + who; }

    @BeforeEach void fixtures() {
        for (String id : List.of(company, other)) db.update("INSERT INTO companies(id,name) VALUES (?,?)", id, id);
        for (String who : List.of("applicant", "reviewer", "outsider", "owner", "participant", "pending", "initial")) {
            var tenant = who.equals("outsider") ? other : company;
            var role = Set.of("applicant", "reviewer", "outsider", "initial").contains(who) ? "ADMIN" : "EMPLOYEE";
            db.update("""
                    INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status,must_change_password)
                    VALUES (?,?,?,'x',?,?,?,?,?)
                    """, uid(who), tenant, uid(who), who, "d-" + uid(who), role,
                    who.equals("pending") ? "PENDING" : "ACTIVE", who.equals("initial"));
            String token = UUID.randomUUID().toString();
            tokens.put(who, token);
            db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')", Db.hash(token), uid(who));
        }
        db.update("INSERT INTO reporting_relations(company_id,employee_id,manager_id) VALUES (?,?,?)",
                company, uid("applicant"), uid("reviewer"));
    }

    JsonNode call(int status, String method, String path, String who, Object body, String key) throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api" + path))
                .timeout(Duration.ofSeconds(15)).header("Authorization", "Bearer " + tokens.get(who));
        if (key != null) request.header("Idempotency-Key", key);
        if (body != null) request.header("Content-Type", "application/json");
        var response = http.send(request.method(method, body == null ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
        assertEquals(status, response.statusCode(), response.body());
        return json.readTree(response.body());
    }

    String customer(String who) throws Exception {
        return call(201, "POST", "/customers", who, Map.of("kind", "ENTERPRISE", "name", "Example"), null).path("id").asText();
    }

    Map<String, Object> record(String customerId) {
        return new HashMap<>(Map.of("customerId", customerId, "kind", "COMPANY_VISIT", "title", "Factory visit",
                "businessDate", "2026-11-26", "ownerId", uid("owner"), "participants", List.of(uid("participant"))));
    }

    JsonNode detail(String id) throws Exception { return call(200, "GET", DELIVERIES + "/" + id, "applicant", null, null); }
    Map<String, Object> command(String action, int version) {
        return Map.of("action", action, "version", version, "reason", "Verified");
    }
    JsonNode change(int status, String id, Object command, String key) throws Exception {
        return call(status, "POST", DELIVERIES + "/" + id + "/changes", "applicant", command, key);
    }
    JsonNode decide(int status, String request, String who, boolean approve, int version, String reason) throws Exception {
        return call(status, "POST", "/reviews/" + request + "/decision", who,
                Map.of("approve", approve, "expectedVersion", version, "reason", reason), null);
    }

    @Test void runtimeContractExposesOfflineOperations() throws Exception {
        var contract = call(200, "GET", "/openapi", "applicant", null, null);
        var paths = contract.path("paths");
        assertEquals("listOfflineDeliveries", paths.path("/api" + DELIVERIES).at("/get/operationId").asText());
        assertTrue(paths.path("/api" + DELIVERIES).at("/post/responses").has("201"));
        assertTrue(paths.path("/api" + DELIVERIES + "/{id}/changes").at("/post/responses").has("202"));
        assertTrue(paths.path("/api" + DELIVERIES + "/employees").has("get"));
        assertTrue(paths.path("/api" + DELIVERIES + "/{id}").has("get"));
        assertTrue(paths.path("/api/reviews/{id}/withdraw-offline").has("post"));
        assertTrue(paths.path("/api/hr/contracts").has("post"));
        assertTrue(paths.path("/api/customers/{id}/membership").has("put"));
        assertTrue(paths.path("/api/commerce/orders").has("get"));
        Files.writeString(Path.of("target", "offline-delivery-openapi.json"),
                json.writerWithDefaultPrettyPrinter().writeValueAsString(contract));
    }

    @Test void companyVisitEndsBeforeSeparateDeliveryAndBothViewsOpenSameRecord() throws Exception {
        var profile = call(201, "POST", "/customers", "applicant", Map.of(
                "kind", "ENTERPRISE", "name", "Foundry", "ownerId", uid("owner"),
                "contacts", List.of(Map.of("name", "Operations"))), "profile");
        var customerId = profile.path("id").asText();
        String customerPath = "/customers/" + customerId;
        call(200, "PUT", customerPath + "/membership", "applicant", Map.of("mallMemberId", "member-a", "version", 0), null);
        var benefit = call(201, "POST", customerPath + "/benefits", "applicant",
                Map.of("kind", "ANNUAL_CARD", "name", "Annual card", "maxUses", 1,
                        "validFrom", "2020-01-01", "validTo", "2100-12-31"), "benefit");
        var usage = call(201, "POST", customerPath + "/benefits/" + benefit.path("id").asText() + "/redemptions",
                "applicant", Map.of(), "usage");
        assertEquals(0, usage.path("remaining").asInt());
        String boundary = "combined-" + Db.id();
        String payload = json.writeValueAsString(Map.of(
                "members", List.of(Map.of("externalMemberId", "member-a", "status", "ACTIVE",
                        "sourceUpdatedAt", "2026-11-26T09:00:00Z")),
                "orders", List.of(Map.of(
                "externalOrderId", "order-a", "externalMemberId", "member-a", "status", "PAID",
                "currency", "CNY", "amount", "100.00", "orderedAt", "2026-11-26T08:00:00Z",
                "sourceUpdatedAt", "2026-11-26T09:00:00Z"))));
        var uploaded = http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api/commerce/imports"))
                .timeout(Duration.ofSeconds(20)).header("Authorization", "Bearer " + tokens.get("applicant"))
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofString("--" + boundary
                        + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"combined.json\"\r\n"
                        + "Content-Type: application/json\r\n\r\n" + payload + "\r\n--" + boundary + "--\r\n"))
                .build(), HttpResponse.BodyHandlers.ofString());
        assertEquals(200, uploaded.statusCode(), uploaded.body());
        String orderQuery = "/commerce/orders?externalOrderId=order-a&customerId=";
        var rowsForCustomer = call(200, "GET", orderQuery + customerId, "applicant", null, null);
        assertEquals("order-a", rowsForCustomer.path("items").get(0).path("externalOrderId").asText());
        assertEquals(0, call(200, "GET", orderQuery + customer("applicant"), "applicant", null, null).path("total").asInt());
        call(404, "GET", orderQuery + customerId, "outsider", null, null);
        call(403, "GET", customerPath, "owner", null, null);
        var body = record(customerId);
        var created = call(201, "POST", DELIVERIES, "applicant", body, "new");
        assertEquals(created, call(201, "POST", DELIVERIES, "applicant", body, "new"));
        String id = created.path("id").asText();
        assertEquals("SCHEDULED", detail(id).path("activityStatus").asText());
        change(409, id, command("CONFIRM_DELIVERY", 1), "early");

        var end = change(202, id, command("END_ACTIVITY", 1), "end");
        assertEquals(end, change(202, id, command("END_ACTIVITY", 1), "end"));
        var review = end.path("reviewId").asText();
        assertEquals("SCHEDULED", detail(id).path("activityStatus").asText());
        change(409, id, command("END_ACTIVITY", 1), "second");
        decide(403, review, "applicant", true, 1, "");
        decide(400, review, "reviewer", false, 1, " ");
        decide(200, review, "reviewer", true, 1, "");
        assertEquals(end, change(202, id, command("END_ACTIVITY", 1), "end"));
        assertEquals("ENDED", detail(id).path("activityStatus").asText());
        assertEquals("PENDING", detail(id).path("deliveryStatus").asText());
        assertTrue(detail(id).path("deliveredAt").isNull());
        change(409, id, command("CONFIRM_DELIVERY", 1), "stale");
        var delivery = change(202, id, command("CONFIRM_DELIVERY", 2), "delivery").path("reviewId").asText();
        decide(200, delivery, "reviewer", true, 2, "");
        assertEquals("DELIVERED", detail(id).path("deliveryStatus").asText());
        assertEquals(3, detail(id).path("version").asInt());
        assertFalse(detail(id).path("deliveredAt").isNull());

        for (String filter : List.of("customerId=" + customerId, "employeeId=" + uid("owner"),
                "employeeId=" + uid("participant"))) {
            var rows = call(200, "GET", DELIVERIES + "?" + filter, "applicant", null, null);
            assertEquals(id, rows.path("items").get(0).path("id").asText());
            assertTrue(rows.path("nextCursor").isNull());
            assertEquals(0, call(200, "GET", DELIVERIES + "?" + filter + "&pendingOnly=true",
                    "applicant", null, null).path("total").asInt());
        }
        assertEquals(2, db.count("SELECT count(*) FROM audit_records WHERE company_id=? AND object_id=? AND type='REVISION_APPLIED'", company, id));
    }

    @Test void authorizationRevocationAndUnassignedWithdrawalDoNotExposeCandidate() throws Exception {
        String customer = customer("applicant");
        String outsideCustomer = customer("outsider");
        call(404, "POST", DELIVERIES, "applicant", record(outsideCustomer), "cross");
        call(403, "POST", DELIVERIES, "owner", record(customer), "staff");
        call(403, "GET", DELIVERIES + "/employees", "initial", null, null);
        for (String invalid : List.of("outsider", "pending")) {
            var draft = record(customer);
            draft.put("ownerId", uid(invalid));
            call(400, "POST", DELIVERIES, "applicant", draft, "invalid-" + invalid);
        }
        String id = call(201, "POST", DELIVERIES, "applicant", record(customer), "new").path("id").asText();
        call(404, "GET", DELIVERIES + "/" + id, "outsider", null, null);
        call(404, "GET", DELIVERIES + "?employeeId=" + uid("outsider"), "applicant", null, null);
        call(404, "GET", DELIVERIES + "?customerId=" + customer, "outsider", null, null);
        call(400, "GET", DELIVERIES + "?customerId=" + customer + "&employeeId=" + uid("owner"), "applicant", null, null);

        String review = change(202, id, command("END_ACTIVITY", 1), "end").path("reviewId").asText();
        db.update("UPDATE users SET role='LEADER' WHERE id=?", uid("reviewer"));
        call(403, "GET", "/reviews/" + review, "reviewer", null, null);
        assertEquals(0, call(200, "GET", "/reviews", "reviewer", null, null).path("total").asInt());
        decide(403, review, "reviewer", true, 1, "");
        var reroute = call(200, "POST", "/reviews/" + review + "/reroute", "applicant", null, null);
        assertFalse(reroute.path("reviewer_configured").asBoolean());
        assertEquals(1, detail(id).path("version").asInt());
        db.update("UPDATE users SET role='ADMIN' WHERE id=?", uid("reviewer"));
        call(200, "POST", "/reviews/" + review + "/reroute", "applicant", null, null);
        call(200, "GET", "/reviews/" + review, "reviewer", null, null);
        db.update("UPDATE users SET role='LEADER' WHERE id=?", uid("applicant"));
        call(403, "GET", "/reviews/" + review, "applicant", null, null);
        assertEquals(0, call(200, "GET", "/reviews", "applicant", null, null).path("total").asInt());
        call(403, "GET", "/reviews/" + review, "reviewer", null, null);
        assertEquals(0, call(200, "GET", "/reviews", "reviewer", null, null).path("total").asInt());
        decide(403, review, "reviewer", true, 1, "");
        var withdrawal = call(200, "POST", "/reviews/" + review + "/withdraw-offline", "reviewer", null, null);
        assertEquals("SUPERSEDED", withdrawal.path("status").asText());
        assertEquals(withdrawal, call(200, "POST", "/reviews/" + review + "/withdraw-offline", "reviewer", null, null));
        db.update("UPDATE users SET role='ADMIN' WHERE id=?", uid("applicant"));
        assertEquals("SCHEDULED", detail(id).path("activityStatus").asText());
        change(202, id, command("END_ACTIVITY", 1), "resubmit");
    }

    @Test void parallelReplayPaginationAndReviewedEditValidateCurrentEmployees() throws Exception {
        var customer = customer("applicant");
        var body = record(customer);
        var start = new CyclicBarrier(2);
        Callable<JsonNode> attempt = () -> {
            start.await(5, TimeUnit.SECONDS);
            return call(201, "POST", DELIVERIES, "applicant", body, "parallel");
        };
        String id;
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            var first = executor.submit(attempt);
            var second = executor.submit(attempt);
            var receipt = first.get(20, TimeUnit.SECONDS);
            assertEquals(receipt, second.get(20, TimeUnit.SECONDS));
            id = receipt.path("id").asText();
        }
        body.put("title", "Updated");
        call(409, "POST", DELIVERIES, "applicant", body, "parallel");
        call(201, "POST", DELIVERIES, "applicant", body, "another");
        var page = call(200, "GET", DELIVERIES + "?customerId=" + customer + "&limit=1", "applicant", null, null);
        assertEquals(2, page.path("total").asInt());
        assertEquals("1", page.path("nextCursor").asText());
        var last = call(200, "GET", DELIVERIES + "?customerId=" + customer + "&limit=1&cursor=1", "applicant", null, null);
        assertNotEquals(page.path("items").get(0).path("id"), last.path("items").get(0).path("id"));
        assertTrue(last.path("nextCursor").isNull());

        body.remove("customerId");
        body.putAll(command("EDIT", 1));
        String review = change(202, id, body, "edit").path("reviewId").asText();
        db.update("UPDATE users SET status='DISABLED' WHERE id=?", uid("participant"));
        decide(400, review, "reviewer", true, 1, "");
        assertEquals("Factory visit", detail(id).path("title").asText());
        decide(200, review, "reviewer", false, 1, "Participant unavailable");
        body.put("participants", List.of());
        review = change(202, id, body, "retry-edit").path("reviewId").asText();
        decide(200, review, "reviewer", true, 1, "");
        assertEquals("Updated", detail(id).path("title").asText());
        assertEquals(2, detail(id).path("version").asInt());
    }
}
