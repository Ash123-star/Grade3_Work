package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class TaskRolesTest {
    private static final Map<String, Object> TASK = Map.of("id", "task1", "owner_id", "owner", "issuer_id", "issuer");

    @Test void onePersonMayHoldParticipantIssuerAndAdminRoles() {
        Db db = mock(Db.class); when(db.count(anyString(), any(), any())).thenReturn(1L);
        Actor actor = new Actor("owner", "c1", "ADMIN", "d1", "t1", true, false, false, "ACTIVE");
        var roles = TaskRoles.resolve(db, actor, Map.of("id", "task1", "owner_id", "owner", "issuer_id", "owner"));
        assertEquals(EnumSet.of(TaskStateMachine.Role.PARTICIPANT, TaskStateMachine.Role.ISSUER,
                TaskStateMachine.Role.ADMIN), roles);
    }

    @Test void managerWithReadScopeButNoTaskRoleGetsNoLifecycleRole() {
        Db db = mock(Db.class); when(db.count(anyString(), any(), any())).thenReturn(0L);
        Actor director = new Actor("director", "c1", "DIRECTOR", "d1", "", true, false, false, "ACTIVE");
        assertEquals(EnumSet.of(TaskStateMachine.Role.OTHER), TaskRoles.resolve(db, director, TASK));
    }
}
