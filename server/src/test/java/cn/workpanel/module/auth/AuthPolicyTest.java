package cn.workpanel.module.auth;

import cn.workpanel.ApiError;
import cn.workpanel.module.auth.domain.AuthPolicy;
import cn.workpanel.module.auth.domain.AuthPolicy.LoginState;
import org.junit.jupiter.api.Test;
import java.time.Instant;
import java.util.Map;
import static org.junit.jupiter.api.Assertions.*;

class AuthPolicyTest {
    @Test void fifthFailureLocksAndExactExpiryRestartsAtOne() {
        Instant now = Instant.parse("2026-10-11T00:00:00Z");
        LoginState state = LoginState.clear();
        for (int i = 1; i <= 4; i++) { state = state.fail(now); assertFalse(state.locked(now)); assertEquals(i, state.failures()); }
        state = state.fail(now);
        assertEquals(now.plusSeconds(600), state.lockedUntil());
        assertTrue(state.locked(now.plusSeconds(599)));
        assertSame(state, state.fail(now.plusSeconds(599)));
        assertFalse(state.locked(now.plusSeconds(600)));
        assertEquals(new LoginState(1, null), state.fail(now.plusSeconds(600)));
    }
    @Test void passwordPolicyChecksUtf8BoundaryAndInvalidType() {
        assertEquals("a".repeat(72), AuthPolicy.password(Map.of("p", "a".repeat(72)), "p"));
        assertThrows(ApiError.class, () -> AuthPolicy.password(Map.of("p", "a".repeat(73)), "p"));
        assertThrows(ApiError.class, () -> AuthPolicy.password(Map.of("p", "中".repeat(25)), "p"));
        assertThrows(ApiError.class, () -> AuthPolicy.password(Map.of("p", "short"), "p"));
        assertThrows(ApiError.class, () -> AuthPolicy.password(Map.of("p", 123), "p"));
    }
    @Test void registrationRejectsBadAccountAndPhone() {
        assertDoesNotThrow(() -> AuthPolicy.registration("lyb.test", "13800000009"));
        assertThrows(ApiError.class, () -> AuthPolicy.registration("x", "13800000009"));
        assertThrows(ApiError.class, () -> AuthPolicy.registration("valid", "123"));
    }
}
