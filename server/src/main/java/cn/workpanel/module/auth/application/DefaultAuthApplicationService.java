package cn.workpanel.module.auth.application;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.auth.domain.AuthPolicy;
import cn.workpanel.module.auth.domain.AuthPolicy.LoginState;
import cn.workpanel.module.auth.infrastructure.AuthRepository;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

/** 认证用例实际实现；失败登录事务提交后再返回错误，防止失败计数被回滚。 */
@Service
public class DefaultAuthApplicationService implements AuthApplicationService {
    private final AuthRepository repository;
    private final BCryptPasswordEncoder passwords;
    private final ReviewApplicationService reviews;
    private final TransactionTemplate transactions;
    private final int hours;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();
    private final String dummyHash;

    public DefaultAuthApplicationService(AuthRepository repository, BCryptPasswordEncoder passwords,
            ReviewApplicationService reviews, PlatformTransactionManager manager,
            @Value("${app.session-hours}") int hours,
            @org.springframework.beans.factory.annotation.Qualifier("authClock") Clock clock) {
        this.repository = repository; this.passwords = passwords; this.reviews = reviews;
        this.transactions = new TransactionTemplate(manager); this.hours = hours; this.clock = clock;
        this.dummyHash = passwords.encode(UUID.randomUUID().toString());
    }
    @Override public List<Map<String, Object>> registrationDepartments() { return repository.departments(); }
    @Override @Transactional public Map<String, Object> register(Map<String, Object> command) {
        Db.fields(command, "account", "password", "phone", "name", "departmentId");
        String account = Db.required(command, "account"), phone = Db.required(command, "phone");
        AuthPolicy.registration(account, phone);
        String department = Db.required(command, "departmentId");
        repository.requireDepartment(department);
        String id = Db.id();
        repository.register(id, account, passwords.encode(AuthPolicy.password(command, "password")), phone, Db.required(command, "name"), department);
        Actor actor = Actor.from(repository.user(id));
        var review = reviews.create(actor, "MEMBERSHIP", id, 1, Map.of("status", "PENDING"),
                Map.of("status", "ACTIVE", "departmentId", department), "注册部门归属申请");
        return Map.of("id", id, "role", "EMPLOYEE", "status", "PENDING", "reviewId", review.get("id"), "phoneVerified", false);
    }
    private record LoginResult(Map<String, Object> response, ApiError error) { }
    @Override public Map<String, Object> login(Map<String, Object> command) {
        Db.fields(command, "account", "password");
        String account = Db.required(command, "account"), password = Db.required(command, "password");
        String key = Db.hash(account);
        LoginResult result = Objects.requireNonNull(transactions.execute(status -> {
            Instant now = clock.instant();
            LoginState state = repository.lockLogin(key, now);
            if (state.locked(now)) return invalid();
            var users = repository.account(account);
            boolean valid = passwords.matches(password, users.isEmpty() ? dummyHash : Db.str(users.getFirst(), "password_hash"));
            if (!valid || users.isEmpty()) {
                repository.saveLogin(key, state.fail(now), now);
                return invalid();
            }
            repository.saveLogin(key, LoginState.clear(), now);
            var user = users.getFirst();
            if (Db.str(user, "status").equals("DISABLED"))
                return new LoginResult(null, new ApiError(403, "ACCOUNT_DISABLED", "账号已停用"));
            byte[] bytes = new byte[32]; random.nextBytes(bytes);
            String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
            Instant expires = now.plusSeconds(hours * 3600L);
            repository.session(token, Db.str(user, "id"), expires);
            return new LoginResult(Map.of("token", token, "expiresAt", expires.toString(), "user", publicUser(user)), null);
        }));
        if (result.error() != null) throw result.error();
        return result.response();
    }
    private static LoginResult invalid() { return new LoginResult(null, new ApiError(401, "INVALID_CREDENTIALS", "账号或密码错误")); }
    @Override public Map<String, Object> current(ActorContext actor) { return publicUser(currentUser(actor, false)); }
    @Override @Transactional public Map<String, Object> changePassword(ActorContext actor, Map<String, Object> command) {
        Db.fields(command, "oldPassword", "newPassword");
        var user = currentUser(actor, true);
        if (!passwords.matches(Db.required(command, "oldPassword"), Db.str(user, "password_hash")))
            throw new ApiError(401, "INVALID_CREDENTIALS", "原密码错误");
        String password = AuthPolicy.password(command, "newPassword");
        if (passwords.matches(password, Db.str(user, "password_hash")))
            throw ApiError.bad("PASSWORD_UNCHANGED", "新密码需与原密码不同");
        repository.password(Actor.from(user), passwords.encode(password));
        return Map.of("reloginRequired", true);
    }
    @Override public Map<String, Object> logout(ActorContext actor, String token) {
        currentUser(actor, false);
        repository.revoke(token, actor.userId());
        return Map.of("ok", true);
    }
    private Map<String, Object> currentUser(ActorContext actor, boolean lock) {
        var user = lock ? repository.lockedUser(actor.userId()) : repository.user(actor.userId());
        if (!Db.str(user, "company_id").equals(actor.companyId())) throw ApiError.forbidden();
        if (Db.str(user, "status").equals("DISABLED")) throw new ApiError(401, "SESSION_EXPIRED", "会话失效");
        return user;
    }
    public static Map<String, Object> publicUser(Map<String, Object> user) {
        var result = new LinkedHashMap<String, Object>();
        for (String key : List.of("id", "name", "department_id", "team_id", "role", "status", "version", "must_change_password", "dispatch_enabled", "company_reviewer"))
            result.put(key, user.get(key));
        return result;
    }
    /** 清理至少 24 小时未更新且已解锁的状态，活跃锁定不会被删除。 */
    @org.springframework.scheduling.annotation.Scheduled(fixedDelay = 3600000, initialDelay = 3600000)
    @Transactional public void cleanLoginStates() {
        Instant now = clock.instant();
        repository.cleanLoginStates(now.minus(Duration.ofDays(1)), now);
    }
    @Transactional public void initializeAdministrator(String account, String password, String phone) {
        if (repository.hasAdministrator()) return;
        if (!account.matches("[a-zA-Z0-9_.-]{3,64}") || password.length() < 12 || password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > 72 || !phone.matches("1[3-9][0-9]{9}"))
            throw new IllegalStateException("首次启动需提供有效 ADMIN_ACCOUNT、至少 12 字符且不超过 72 字节的 ADMIN_PASSWORD 和 ADMIN_PHONE");
        if (repository.occupied(account, phone)) throw new IllegalStateException("初始化账号已存在，不覆盖现有账号");
        repository.administrator(Db.id(), account, passwords.encode(password), phone);
    }
}
