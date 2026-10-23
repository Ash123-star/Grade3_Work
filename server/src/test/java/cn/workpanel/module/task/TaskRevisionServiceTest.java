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

class TaskRevisionServiceTest {
    private static final Actor ISSUER = new Actor("issuer", "c1", "LEADER", "d1", "t1", true, false, false, "ACTIVE");
    private Db db;
    private TaskRevisionService service;

    @BeforeEach void setUp() {
        db = mock(Db.class); service = new TaskRevisionService(db);
        when(db.rows(anyString(), any(Object[].class))).thenReturn(List.of(task("RECEIVED", 2)));
        when(db.count(anyString(), any(), any())).thenReturn(0L);
        when(db.read(any())).thenReturn(Map.of("ownerId", "owner", "deadline", "2026-10-20T18:00+08:00", "collaborators", List.of("helper")));
        when(db.write(any())).thenReturn("{}");
    }

    @Test void reassignmentRejectsSameOwnerWithoutCreatingReview() {
        var error = assertThrows(ApiError.class, () -> service.prepareReassignment(ISSUER, "task1",
                Map.of("ownerId", "owner", "version", 2, "reason", "重复负责人")));
        assertEquals("SAME_OWNER", error.code);
        verify(db, never()).update(contains("review_requests"), any(Object[].class));
    }

    @Test void rescheduleRejectsTimezoneLessAndSameDeadline() {
        assertEquals("INVALID_DATE", code(() -> service.prepareReschedule(ISSUER, "task1",
                Map.of("deadline", "2026-10-20", "version", 2, "reason", "格式错误"))));
        assertEquals("INVALID_DEADLINE", code(() -> service.prepareReschedule(ISSUER, "task1",
                Map.of("deadline", "2026-10-20T10:00Z", "version", 2, "reason", "相同时间"))));
    }

    @Test void rescheduleApplyKeepsPhaseAndWritesVersionedTimeline() {
        var current = task("FEEDBACK", 2);
        when(db.update(anyString(), any(Object[].class))).thenReturn(1);
        when(db.one(anyString(), any(Object[].class))).thenReturn(Map.of("issuer_id", "issuer"));
        service.applyReschedule(db, ISSUER, current, 2,
                Map.of("deadline", "2026-10-21T18:00+08:00"), "延期说明");
        verify(db).update(contains("SET deadline=?::timestamptz,body=?::jsonb,version=?"),
                eq("2026-10-21T18:00+08:00"), anyString(), eq(3), eq("task1"), eq(2));
        verify(db).update(contains("INSERT INTO task_events"), eq("c1"), eq("task1"), eq("issuer"),
                eq("RESCHEDULED"), anyString(), eq("FEEDBACK"), eq("FEEDBACK"), eq(3));
    }

    @Test void reassignmentReplacesPrimaryRemovesBothOldAndNewCollaboratorsAndResetsPhase() {
        var current = task("FEEDBACK", 2);
        when(db.rows(startsWith("SELECT * FROM users"), eq("next-owner"), eq("c1")))
                .thenReturn(List.of(Map.of("id", "next-owner", "company_id", "c1", "department_id", "d1", "team_id", "t1")));
        when(db.rows(startsWith("SELECT user_id FROM task_participants"), any())).thenReturn(List.of());
        when(db.update(anyString(), any(Object[].class))).thenReturn(1);
        when(db.one(anyString(), any(Object[].class))).thenReturn(Map.of("issuer_id", "issuer"));
        service.applyReassignment(db, ISSUER, current, 2, Map.of("ownerId", "next-owner"), "职责调整");
        verify(db).update(contains("SET owner_id=?,body=?::jsonb,phase='DISPATCHED',version=?"),
                eq("next-owner"), anyString(), eq(3), eq("task1"), eq(2));
        verify(db).update(contains("DELETE FROM task_participants WHERE task_id=? AND user_id=?"),
                eq("task1"), eq("owner"));
        verify(db).update(contains("INSERT INTO task_participants"), eq("task1"), eq("next-owner"), eq("c1"));
        verify(db).update(contains("INSERT INTO task_events"), eq("c1"), eq("task1"), eq("issuer"),
                eq("REASSIGNED"), anyString(), eq("FEEDBACK"), eq("DISPATCHED"), eq(3));
    }

    private static String code(Runnable runnable) { return assertThrows(ApiError.class, runnable::run).code; }

    private static Map<String, Object> task(String phase, int version) {
        return new HashMap<>(Map.of("id", "task1", "owner_id", "owner", "issuer_id", "issuer", "phase", phase,
                "version", version, "body", "{}"));
    }
}
