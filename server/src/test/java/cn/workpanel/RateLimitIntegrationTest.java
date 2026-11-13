package cn.workpanel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;

/** 隔离 PostgreSQL/Redis 验证实际入口额度；外部模型仅连接本机 HTTP 夹具。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001", "app.deepseek-key=local-rate-limit-test-only",
    "app.jobs-enabled=false", "app.memory-extract-enabled=false"
})
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
class RateLimitIntegrationTest {
    static final ObjectMapper JSON = new ObjectMapper();
    static final String PASSWORD = "Rate-limit-test-password-2026";
    static final AtomicInteger providerCalls = new AtomicInteger();
    static final HttpServer provider = startProvider();
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired StringRedisTemplate redis;
    @Autowired BCryptPasswordEncoder passwords;
    @Autowired MemoryModel memoryModel;
    final HttpClient http = HttpClient.newHttpClient();
    Actor actor;
    String token;

    @DynamicPropertySource static void providerUrl(DynamicPropertyRegistry properties) {
        properties.add("app.deepseek-url", () -> "http://127.0.0.1:" + provider.getAddress().getPort());
    }

    static HttpServer startProvider() {
        try {
            var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/chat/completions", exchange -> {
                exchange.getRequestBody().readAllBytes();
                providerCalls.incrementAndGet();
                byte[] response = JSON.writeValueAsBytes(Map.of("choices", List.of(Map.of("message",
                    Map.of("content", "{\"ok\":true}"))), "usage", Map.of("total_tokens", 10)));
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, response.length);
                try (var output = exchange.getResponseBody()) { output.write(response); }
                exchange.close();
            });
            server.start();
            return server;
        } catch (Exception e) { throw new ExceptionInInitializerError(e); }
    }

    @AfterAll static void stopProvider() { provider.stop(0); }

    @BeforeEach void fixture() {
        String id = Db.id(), account = "rate-" + id.substring(0, 12);
        String phone = "138" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000));
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,role,status) VALUES (?,'default',?,?,?,?,'product','EMPLOYEE','ACTIVE')",
            id, account, passwords.encode(PASSWORD), phone, account);
        db.update("INSERT INTO user_roles VALUES (?,'EMPLOYEE')", id);
        actor = Actor.from(db.one("SELECT * FROM users WHERE id=?", id));
        token = Db.id();
        db.update("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES (?,?,now()+interval '1 hour')", Db.hash(token), id);
        redis.delete(List.of("workpanel:register:127.0.0.1", "workpanel:login:127.0.0.1"));
    }

    HttpResponse<String> request(String method, String path, String bearer, Object body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api" + path))
            .timeout(Duration.ofSeconds(15));
        if (bearer != null) builder.header("Authorization", "Bearer " + bearer);
        if (body != null) builder.header("Content-Type", "application/json");
        return http.send(builder.method(method, body == null ? HttpRequest.BodyPublishers.noBody()
            : HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
    }

    void seed(String key, int count) {
        redis.opsForValue().set("workpanel:" + key, Integer.toString(count), Duration.ofSeconds(30));
    }

    void rateLimited(HttpResponse<String> response) throws Exception {
        assertEquals(429, response.statusCode(), response.body());
        JsonNode error = JSON.readTree(response.body());
        assertEquals("RATE_LIMITED", error.get("code").asText());
        assertTrue(error.hasNonNull("traceId"));
        long retry = Long.parseLong(response.headers().firstValue("Retry-After").orElseThrow());
        assertTrue(retry >= 1 && retry <= 30, "重试应使用原窗口剩余时间");
    }

    @Test void registrationAllowsFiftiethRejectsFiftyFirstAndRecoversOnExpiry() throws Exception {
        String key = "register:127.0.0.1";
        seed(key, 49);
        // 无效输入仍计数，确保第50次已进入注册业务校验，第51次才被限流拦截。
        var allowed = request("POST", "/auth/register", null, Map.of());
        assertEquals(400, allowed.statusCode());
        assertEquals("INVALID_FIELD", JSON.readTree(allowed.body()).get("code").asText());
        rateLimited(request("POST", "/auth/register", null, Map.of()));
        assertEquals("51", redis.opsForValue().get("workpanel:" + key));
        redis.expire("workpanel:" + key, Duration.ZERO);
        assertEquals(400, request("POST", "/auth/register", null, Map.of()).statusCode());
        assertEquals("1", redis.opsForValue().get("workpanel:" + key));
        assertTrue(redis.getExpire("workpanel:" + key) > 3500, "注册仍采用一小时窗口");
    }

    @Test void loginAllowsOneHundredFiftiethAndRejectsNext() throws Exception {
        seed("login:127.0.0.1", 149);
        Map<String, Object> command = Map.of("account", db.one("SELECT account FROM users WHERE id=?", actor.id()).get("account"), "password", PASSWORD);
        var allowed = request("POST", "/auth/login", null, command);
        assertEquals(200, allowed.statusCode(), allowed.body());
        assertTrue(JSON.readTree(allowed.body()).hasNonNull("token"));
        rateLimited(request("POST", "/auth/login", null, command));
    }

    @Test void authenticatedRequestsAllowSixHundredAndKeepUsersIsolated() throws Exception {
        String firstToken = token;
        String firstId = actor.id();
        seed("api:" + firstId, 599);
        var allowed = request("GET", "/auth/me", firstToken, null);
        assertEquals(200, allowed.statusCode(), allowed.body());
        rateLimited(request("GET", "/auth/me", firstToken, null));
        fixture();
        assertEquals(200, request("GET", "/auth/me", token, null).statusCode());
        assertEquals("601", redis.opsForValue().get("workpanel:api:" + firstId));
    }

    @Test void aiJobAllowsTwentyFifthAndRejectsNextBeforeCreatingJob() throws Exception {
        seed("ai:" + actor.id(), 24);
        Map<String, Object> command = Map.of("date", LocalDate.now(ZoneId.of("Asia/Shanghai")).toString(), "period", "day", "scope", "SELF");
        var allowed = request("POST", "/ai/jobs", token, command);
        assertEquals(200, allowed.statusCode(), allowed.body());
        rateLimited(request("POST", "/ai/jobs", token, command));
        assertEquals(1, db.count("SELECT count(*) FROM ai_jobs WHERE owner_id=?", actor.id()));
    }

    @Test void memoryModelAllowsTwentyFifthAndRejectsNextBeforeCallingProvider() throws Exception {
        seed("memory-model:" + actor.id(), 24);
        int before = providerCalls.get();
        var answer = memoryModel.complete(actor, "RATE_LIMIT_TEST", "Return JSON", Map.of());
        assertEquals(true, answer.json().get("ok"));
        ApiError error = assertThrows(ApiError.class,
            () -> memoryModel.complete(actor, "RATE_LIMIT_TEST", "Return JSON", Map.of()));
        assertEquals(429, error.status);
        assertEquals("RATE_LIMITED", error.code);
        assertTrue(error.retryAfterSeconds >= 1 && error.retryAfterSeconds <= 30);
        assertEquals(before + 1, providerCalls.get(), "超额调用不能到达供应商");
    }
}
