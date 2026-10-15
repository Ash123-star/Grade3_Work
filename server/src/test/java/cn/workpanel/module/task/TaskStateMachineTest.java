package cn.workpanel.module.task;

import org.junit.jupiter.api.Test;
import java.util.EnumSet;
import static org.junit.jupiter.api.Assertions.*;

/** 状态表全量回归：六个状态、八个动作和五种典型角色组合。 */
class TaskStateMachineTest {
    private static final EnumSet<TaskStateMachine.Role> PRIMARY = EnumSet.of(TaskStateMachine.Role.PRIMARY);
    private static final EnumSet<TaskStateMachine.Role> COLLABORATOR = EnumSet.of(TaskStateMachine.Role.COLLABORATOR);
    private static final EnumSet<TaskStateMachine.Role> ISSUER = EnumSet.of(TaskStateMachine.Role.ISSUER);
    private static final EnumSet<TaskStateMachine.Role> ADMIN = EnumSet.of(TaskStateMachine.Role.ADMIN);
    private static final EnumSet<TaskStateMachine.Role> READER = EnumSet.of(TaskStateMachine.Role.OTHER);

    @Test void exhaustiveStateActionRoleMatrixMatchesSpecification() {
        for (var phase : TaskStateMachine.Phase.values()) {
            for (var action : TaskStateMachine.Action.values()) {
                assertDecision(phase, action, PRIMARY, expected(phase, action, true, false, false));
                assertDecision(phase, action, COLLABORATOR, expected(phase, action, false, true, false));
                assertDecision(phase, action, ISSUER, expected(phase, action, false, false, true));
                assertDecision(phase, action, ADMIN, expected(phase, action, false, false, true));
                assertDecision(phase, action, READER, TaskStateMachine.Result.FORBIDDEN);
            }
        }
    }

    @Test void multiRoleKeepsEveryPermittedCapability() {
        var roles = EnumSet.of(TaskStateMachine.Role.PRIMARY, TaskStateMachine.Role.ISSUER);
        assertEquals(TaskStateMachine.Result.ALLOWED,
                TaskStateMachine.decide(TaskStateMachine.Phase.DISPATCHED, TaskStateMachine.Action.RECEIVED, roles).result());
        assertEquals(TaskStateMachine.Result.ALLOWED,
                TaskStateMachine.decide(TaskStateMachine.Phase.DISPATCHED, TaskStateMachine.Action.WITHDRAWN, roles).result());
    }

    private static TaskStateMachine.Result expected(TaskStateMachine.Phase phase, TaskStateMachine.Action action,
            boolean primary, boolean collaborator, boolean issuer) {
        boolean permitted = switch (action) {
            case RECEIVED -> primary;
            case FEEDBACK -> primary || collaborator;
            default -> issuer;
        };
        if (!permitted) return TaskStateMachine.Result.FORBIDDEN;
        boolean allowed = switch (action) {
            case RECEIVED -> phase == TaskStateMachine.Phase.DISPATCHED;
            case FEEDBACK -> phase == TaskStateMachine.Phase.RECEIVED || phase == TaskStateMachine.Phase.FEEDBACK;
            case ACCEPTED, RETURNED -> phase == TaskStateMachine.Phase.FEEDBACK;
            case ARCHIVED -> phase == TaskStateMachine.Phase.ACCEPTED;
            case WITHDRAWN -> phase == TaskStateMachine.Phase.DISPATCHED || phase == TaskStateMachine.Phase.RECEIVED || phase == TaskStateMachine.Phase.FEEDBACK;
            case REASSIGN, RESCHEDULE -> !phase.terminal();
        };
        return allowed ? TaskStateMachine.Result.ALLOWED : TaskStateMachine.Result.INVALID_TRANSITION;
    }

    private static void assertDecision(TaskStateMachine.Phase phase, TaskStateMachine.Action action,
            EnumSet<TaskStateMachine.Role> roles, TaskStateMachine.Result expected) {
        assertEquals(expected, TaskStateMachine.decide(phase, action, roles).result(),
                () -> phase + " " + action + " " + roles);
    }
}
