package cn.workpanel.bootstrap;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import javax.sql.DataSource;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class ScenarioDataBootstrapTest {
    @Test void invalidPasswordNeverAccessesDatabase() {
        var source = mock(DataSource.class);
        for (String invalid : new String[]{"", "short", " ".repeat(20), "界".repeat(25)}) {
            var runner = new ScenarioDataBootstrap(source, new BCryptPasswordEncoder(), invalid);
            assertThrows(IllegalArgumentException.class, () -> runner.run(null));
        }
        verifyNoInteractions(source);
    }

    @Test void validUnicodePasswordFitsBcryptAndExplicitOptInIsRequired() {
        assertDoesNotThrow(() -> ScenarioDataBootstrap.requirePassword("123456"));
        assertDoesNotThrow(() -> ScenarioDataBootstrap.requirePassword("场景密码安全校验十二字符以上"));
        var condition = ScenarioDataBootstrap.class.getAnnotation(ConditionalOnProperty.class);
        assertEquals("true", condition.havingValue());
        assertFalse(condition.matchIfMissing());
        assertArrayEquals(new String[]{"app.scenario-data-enabled"}, condition.name());
    }
}
