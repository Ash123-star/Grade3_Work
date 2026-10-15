package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 生命周期应用服务的判定顺序与无副作用失败分支。 */
class TaskLifecycleServiceTest {
    private static final Actor OWNER = new Actor("owner", "c1", "EMPLOYEE", "d1", "t1", false, false, false, "ACTIVE");
    private Db db;
    private TaskLifecycleService service;

    @BeforeEach void setUp() {
        db = mock(Db.class);
        service = new TaskLifecycleService(db);
        when(db.rows(anyString(), any(Object[].class))).thenReturn(List.of(task("FEEDBACK", 2)));
        when(db.count(anyString(), any(), any())).thenReturn(0L);
    }

    @Test void staleVersionWinsOverInvalidStateAndDoesNotAppendEvent() {
        var error = assertThrows(ApiError.class, () -> service.apply(OWNER, "task1",
                Map.of("type", "RECEIVED", "version", 1)));
        assertEquals("VERSION_CONFLICT", error.code);
        verify(db, never()).update(contains("UPDATE tasks SET phase"), any(Object[].class));
        verify(db, never()).update(contains("INSERT INTO task_events"), any(Object[].class));
        verify(db, never()).audit(any(), anyString(), anyString(), any(), any(), anyString());
    }

    @Test void invalidTransitionDoesNotWriteStateOrTimeline() {
        when(db.rows(anyString(), any(Object[].class))).thenReturn(List.of(task("DISPATCHED", 1)));
        var error = assertThrows(ApiError.class, () -> service.apply(OWNER, "task1",
                Map.of("type", "FEEDBACK", "version", 1, "text", "进度")));
        assertEquals("INVALID_TRANSITION", error.code);
        verify(db, never()).update(contains("UPDATE tasks SET phase"), any(Object[].class));
        verify(db, never()).update(contains("INSERT INTO task_events"), any(Object[].class));
    }

    @Test void readableButUnassignedManagerIsForbiddenBeforeVersionCheck() {
        Actor director = new Actor("director", "c1", "DIRECTOR", "d1", "", true, false, false, "ACTIVE");
        var error = assertThrows(ApiError.class, () -> service.apply(director, "task1",
                Map.of("type", "ACCEPTED", "version", 1)));
        assertEquals("FORBIDDEN", error.code);
    }

    private static Map<String, Object> task(String phase, int version) {
        return new HashMap<>(Map.of("id", "task1", "owner_id", "owner", "issuer_id", "issuer",
                "phase", phase, "version", version, "body", "{}"));
    }
}
