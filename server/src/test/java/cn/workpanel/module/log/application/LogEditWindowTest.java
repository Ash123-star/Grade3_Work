package cn.workpanel.module.log.application;

import cn.workpanel.*;
import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class LogEditWindowTest {
    final Instant start=Instant.parse("2026-10-19T00:00:00Z");
    @Test void exclusiveTwentyFourHourBoundary() {
        var log=Map.<String,Object>of("submitted",true,"submitted_at",java.sql.Timestamp.from(start));
        assertTrue(LogEditWindow.open(log,start.plusSeconds(86340)));
        assertTrue(LogEditWindow.open(log,start.plusSeconds(86400).minusNanos(1)));
        assertFalse(LogEditWindow.open(log,start.plusSeconds(86400)));
        var error=assertThrows(ApiError.class,()->LogEditWindow.requireOpen(log,start.plusSeconds(86401)));
        assertEquals("LOG_EDIT_WINDOW_EXPIRED",error.code);
    }
    @Test void withdrawnDraftDoesNotResetDeadlineAndLegacyMissingTimeFailsClosed() {
        assertFalse(LogEditWindow.open(Map.of("submitted",false,"submitted_at",start),start.plusSeconds(86400)));
        assertFalse(LogEditWindow.open(Map.of("submitted",true),start));
        assertTrue(LogEditWindow.open(Map.of("submitted",false),start));
    }
}
