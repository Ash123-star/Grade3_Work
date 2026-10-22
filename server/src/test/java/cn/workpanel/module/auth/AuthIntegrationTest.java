package cn.workpanel.module.auth;

import cn.workpanel.Db;
import cn.workpanel.module.auth.infrastructure.AuthRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 真实 HTTP/PostgreSQL/Redis 认证链路，独立随机账号，不依赖测试顺序。 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026", "app.admin-phone=13900000001"
})
class AuthIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired AuthRepository repository;
    @Autowired StringRedisTemplate redis;
    @Autowired BCryptPasswordEncoder passwords;
    @Autowired PlatformTransactionManager manager;
    @Autowired javax.sql.DataSource dataSource;
    static final String PASSWORD = "Employee-test-password-2026";
    static final ObjectMapper JSON = new ObjectMapper();
    final HttpClient http = HttpClient.newHttpClient();
    String account, id;

    @BeforeEach void fixture() {
        account = "auth-" + UUID.randomUUID().toString().substring(0, 12); id = Db.id();
        String phone = "138" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000));
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,role,status) VALUES (?,'default',?,?,?,?,'product','EMPLOYEE','PENDING')", id, account, passwords.encode(PASSWORD), phone, account);
        db.update("INSERT INTO user_roles VALUES (?,'EMPLOYEE')", id);
        redis.delete(List.of("workpanel:login:127.0.0.1", "workpanel:register:127.0.0.1"));
    }
    HttpResponse<String> request(String method, String path, String token, Object body) throws Exception {
        var builder = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + "/api" + path)).timeout(Duration.ofSeconds(20));
        if (token != null) builder.header("Authorization", "Bearer " + token);
        if (body != null) builder.header("Content-Type", "application/json");
        return http.send(builder.method(method, body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(), HttpResponse.BodyHandlers.ofString());
    }
    JsonNode call(int expected, String method, String path, String token, Object body) throws Exception {
        var response = request(method, path, token, body);
        assertEquals(expected, response.statusCode(), path + " " + response.body());
        assertTrue(response.headers().firstValue("X-Trace-Id").isPresent());
        return JSON.readTree(response.body());
    }
    JsonNode login(String password, int status) throws Exception { return call(status, "POST", "/auth/login", null, Map.of("account", account, "password", password)); }
    String token() throws Exception { return login(PASSWORD, 200).get("token").asText(); }

    @Test void failedLoginPersistsLocksExpiresAndSuccessClears() throws Exception {
        for (int i = 1; i <= 5; i++) {
            assertEquals("INVALID_CREDENTIALS", login("wrong-password", 401).get("code").asText());
            assertEquals(i, db.count("SELECT failures FROM auth_login_state WHERE account_hash=?", Db.hash(account)));
        }
        var until = db.one("SELECT locked_until FROM auth_login_state WHERE account_hash=?", Db.hash(account)).get("locked_until");
        login(PASSWORD, 401);
        assertEquals(until, db.one("SELECT locked_until FROM auth_login_state WHERE account_hash=?", Db.hash(account)).get("locked_until"));
        assertEquals(0, db.count("SELECT count(*) FROM sessions WHERE user_id=?", id));
        db.update("UPDATE auth_login_state SET locked_until=now()-interval '1 second' WHERE account_hash=?", Db.hash(account));
        login("wrong-password", 401);
        assertEquals(1, db.count("SELECT failures FROM auth_login_state WHERE account_hash=?", Db.hash(account)));
        token();
        assertEquals(0, db.count("SELECT failures FROM auth_login_state WHERE account_hash=?", Db.hash(account)));
    }

    @Test void concurrentFailuresCannotLoseCounts() throws Exception {
        try (var pool = Executors.newFixedThreadPool(5)) {
            var futures = new ArrayList<Future<Integer>>();
            for (int i = 0; i < 5; i++) futures.add(pool.submit(() -> request("POST", "/auth/login", null, Map.of("account", account, "password", "wrong-password")).statusCode()));
            for (var future : futures) assertEquals(401, future.get(25, TimeUnit.SECONDS));
        }
        assertEquals(5, db.count("SELECT failures FROM auth_login_state WHERE account_hash=?", Db.hash(account)));
        login(PASSWORD, 401);
    }

    @Test void pendingScopeLogoutAndPublicFields() throws Exception {
        String first = token(), second = token();
        var me = call(200, "GET", "/auth/me", first, null);
        for (String field : List.of("password_hash", "phone", "token_hash", "profile")) assertFalse(me.has(field));
        assertEquals("MEMBERSHIP_PENDING", call(403, "GET", "/organization", first, null).get("code").asText());
        call(200, "POST", "/auth/logout", first, null);
        call(401, "GET", "/auth/me", first, null);
        call(401, "POST", "/auth/logout", first, null);
        call(200, "GET", "/auth/me", second, null);
    }

    @Test void passwordChangeRequiresOldPasswordAndRevokesEverySession() throws Exception {
        db.update("UPDATE users SET must_change_password=true,status='ACTIVE' WHERE id=?", id);
        String first = token(), second = token();
        call(403, "GET", "/organization", first, null);
        call(401, "POST", "/auth/password", first, Map.of("oldPassword", "wrong-password", "newPassword", "Changed-test-password-2026"));
        call(400, "POST", "/auth/password", first, Map.of("oldPassword", PASSWORD, "newPassword", PASSWORD));
        call(400, "POST", "/auth/password", first, Map.of("oldPassword", PASSWORD, "newPassword", "short"));
        call(200, "POST", "/auth/password", first, Map.of("oldPassword", PASSWORD, "newPassword", "Changed-test-password-2026"));
        call(401, "GET", "/auth/me", first, null); call(401, "GET", "/auth/me", second, null);
        String changed = login("Changed-test-password-2026", 200).get("token").asText();
        assertFalse(call(200, "GET", "/auth/me", changed, null).get("must_change_password").asBoolean());
    }

    @Test void currentScopeChangesAndDisabledSessionExpires() throws Exception {
        db.update("UPDATE users SET status='ACTIVE' WHERE id=?", id);
        String token = token();
        db.update("UPDATE users SET department_id='engineering' WHERE id=?", id);
        assertEquals("engineering", call(200, "GET", "/auth/me", token, null).get("department_id").asText());
        db.update("UPDATE users SET status='DISABLED' WHERE id=?", id);
        call(401, "GET", "/auth/me", token, null);
        assertEquals("ACCOUNT_DISABLED", login(PASSWORD, 403).get("code").asText());
        assertEquals("INVALID_CREDENTIALS", login("wrong-password", 401).get("code").asText());
    }

    @Test void registrationRejectsInjectionInvalidDepartmentAndDuplicatesAtomically() throws Exception {
        String newAccount = account + "-new";
        var command = new LinkedHashMap<String, Object>(Map.of("account", newAccount, "phone", "137" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000)), "password", PASSWORD, "name", "注册测试", "departmentId", "product"));
        command.put("role", "ADMIN"); call(400, "POST", "/auth/register", null, command); command.remove("role");
        command.put("phone", "123"); call(400, "POST", "/auth/register", null, command);
        command.put("phone", "136" + String.format("%08d", ThreadLocalRandom.current().nextInt(100000000)));
        command.put("departmentId", "missing"); call(404, "POST", "/auth/register", null, command);
        assertEquals(0, db.count("SELECT count(*) FROM users WHERE account=?", newAccount));
        command.put("departmentId", "product");
        var result = call(200, "POST", "/auth/register", null, command);
        assertEquals("EMPLOYEE", result.get("role").asText()); assertEquals("PENDING", result.get("status").asText());
        call(409, "POST", "/auth/register", null, command);
        command.put("account", newAccount + "2"); call(409, "POST", "/auth/register", null, command);
        assertEquals(1, db.count("SELECT count(*) FROM users WHERE phone=?", command.get("phone")));
        assertEquals(0, db.count("SELECT count(*) FROM users WHERE account=?", newAccount + "2"));
    }

    @Test void unknownAccountHasSameErrorAndCleanupPreservesLiveLocks() throws Exception {
        var known = login("wrong-password", 401);
        var unknown = call(401, "POST", "/auth/login", null, Map.of("account", account + "-unknown", "password", "wrong-password"));
        assertEquals(known.get("code"), unknown.get("code")); assertEquals(known.get("message"), unknown.get("message"));
        assertEquals(1, db.count("SELECT failures FROM auth_login_state WHERE account_hash=?", Db.hash(account + "-unknown")));
        db.update("UPDATE auth_login_state SET updated_at=now()-interval '2 days' WHERE account_hash=?", Db.hash(account));
        db.update("UPDATE auth_login_state SET updated_at=now()-interval '2 days',locked_until=now()+interval '10 minutes' WHERE account_hash=?", Db.hash(account + "-unknown"));
        new TransactionTemplate(manager).execute(status -> repository.cleanLoginStates(Instant.now().minus(Duration.ofDays(1)), Instant.now()));
        assertEquals(0, db.count("SELECT count(*) FROM auth_login_state WHERE account_hash=?", Db.hash(account)));
        assertEquals(1, db.count("SELECT count(*) FROM auth_login_state WHERE account_hash=?", Db.hash(account + "-unknown")));
    }

    @Test void migrationUpgradesExistingMainV12SchemaWithoutChangingUsers() {
        String schema = "auth_upgrade_" + UUID.randomUUID().toString().replace("-", "");
        var flyway = org.flywaydb.core.Flyway.configure().dataSource(dataSource).schemas(schema).defaultSchema(schema).target("12").load();
        try {
            flyway.migrate();
            db.update("INSERT INTO " + schema + ".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('existing','default','existing',?,'13800000009','升级保留','EMPLOYEE','PENDING')", passwords.encode(PASSWORD));
            org.flywaydb.core.Flyway.configure().dataSource(dataSource).schemas(schema).defaultSchema(schema).load().migrate();
            assertEquals(1, db.count("SELECT count(*) FROM " + schema + ".users WHERE id='existing' AND status='PENDING'"));
            assertEquals(0, db.count("SELECT count(*) FROM " + schema + ".auth_login_state"));
        } finally {
            // 仅删除本测试生成的独立 schema，不影响 public 或开发数据库。
            db.update("DROP SCHEMA " + schema + " CASCADE");
        }
    }

    @Test void legacyV5AndV10ClonesUpgradeWithoutLosingUsersOrLoginProtection() throws Exception {
        for(int oldVersion: List.of(5,10,12)) {
            String schema="legacy_upgrade_"+UUID.randomUUID().toString().replace("-", "");
            try {
                org.flywaydb.core.Flyway.configure().dataSource(dataSource).schemas(schema).defaultSchema(schema).target(oldVersion==5?"4":oldVersion==10?"9":"11").load().migrate();
                try(var connection=dataSource.getConnection();var statement=connection.createStatement()) {
                    String previousSchema=connection.getSchema();
                    try {
                    connection.setSchema(schema);
                    try(var resource=getClass().getResourceAsStream("/db/migration/V13__auth_login_protection.sql")) {
                        statement.execute(new String(java.util.Objects.requireNonNull(resource).readAllBytes(),java.nio.charset.StandardCharsets.UTF_8));
                    }
                    statement.execute("INSERT INTO flyway_schema_history(installed_rank,version,description,type,script,checksum,installed_by,execution_time,success) SELECT max(installed_rank)+1,'"+oldVersion+"','auth login protection','SQL','V"+oldVersion+"__auth_login_protection.sql',-1773296244,current_user,0,true FROM flyway_schema_history");
                    if(oldVersion==10) statement.execute("INSERT INTO flyway_schema_history(installed_rank,version,description,type,script,checksum,installed_by,execution_time,success) SELECT max(installed_rank)+1,'11','task review kinds','SQL','V11__task_review_kinds.sql',-1563727389,current_user,0,true FROM flyway_schema_history");
                    } finally { connection.setSchema(previousSchema); }
                }
                db.update("INSERT INTO "+schema+".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('legacy','default','legacy','unchanged','13800000008','旧库保留','EMPLOYEE','PENDING')");
                db.update("INSERT INTO "+schema+".auth_login_state(account_hash,failures) VALUES (?,3)",Db.hash("legacy"));
                cn.workpanel.tools.LegacyAuthUpgrade.upgrade(dataSource,schema);
                assertEquals("unchanged",db.one("SELECT password_hash FROM "+schema+".users WHERE id='legacy'").get("password_hash"));
                assertEquals(3,db.count("SELECT failures FROM "+schema+".auth_login_state WHERE account_hash=?",Db.hash("legacy")));
                assertEquals(18,db.count("SELECT count(*) FROM "+schema+".flyway_schema_history WHERE version IS NOT NULL AND success"));
            } finally { db.update("DROP SCHEMA "+schema+" CASCADE"); }
        }
    }

    @Test void legacyUpgradeRefusesOriginalDatabase() {
        assertThrows(IllegalArgumentException.class, () -> cn.workpanel.tools.LegacyAuthUpgrade.upgrade(dataSource,"public"));
    }
    @Test void browserPreflightAllowsConfiguredOriginAndRejectsForeignOrigin() throws Exception {
        for(String origin:List.of("http://localhost:5173","https://untrusted.example")) {
            var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/auth/login"))
                .header("Origin",origin).header("Access-Control-Request-Method","POST")
                .header("Access-Control-Request-Headers","content-type,authorization")
                .method("OPTIONS",HttpRequest.BodyPublishers.noBody()).build();
            var response=HttpClient.newHttpClient().send(request,HttpResponse.BodyHandlers.ofString());
            assertEquals(origin.equals("http://localhost:5173")?200:403,response.statusCode());
            assertEquals(origin.equals("http://localhost:5173")?Optional.of(origin):Optional.empty(),response.headers().firstValue("Access-Control-Allow-Origin"));
        }
    }

}
