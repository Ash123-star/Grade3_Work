package cn.workpanel.module.auth.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;

/** 认证输入与失败防护规则；不访问 HTTP 或数据库。 */
public final class AuthPolicy {
    public static final int FAILURE_LIMIT = 5;
    public static final Duration LOCK_DURATION = Duration.ofMinutes(10);
    private AuthPolicy() { }

    public static String password(Map<String, Object> command, String key) {
        String value = Db.required(command, key);
        if (value.length() < 12 || value.getBytes(StandardCharsets.UTF_8).length > 72)
            throw ApiError.bad("PASSWORD_POLICY", "密码至少 12 个字符，UTF-8 编码不超过 72 字节");
        return value;
    }

    public static void registration(String account, String phone) {
        if (!account.matches("[a-zA-Z0-9_.-]{3,64}") || !phone.matches("1[3-9][0-9]{9}"))
            throw ApiError.bad("INVALID_ACCOUNT", "账号或手机号无效");
    }

    public record LoginState(int failures, Instant lockedUntil) {
        public boolean locked(Instant now) { return lockedUntil != null && now.isBefore(lockedUntil); }
        public LoginState fail(Instant now) {
            if (locked(now)) return this;
            int count = lockedUntil != null ? 1 : failures + 1;
            return new LoginState(count, count >= FAILURE_LIMIT ? now.plus(LOCK_DURATION) : null);
        }
        public static LoginState clear() { return new LoginState(0, null); }
    }
}
