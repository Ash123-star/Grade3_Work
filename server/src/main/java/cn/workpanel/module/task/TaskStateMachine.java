package cn.workpanel.module.task;

import cn.workpanel.ApiError;
import java.util.EnumSet;

/**
 * 任务生命周期的纯领域规则。
 *
 * <p>该类不读取数据库；读取范围、角色解析和乐观锁由应用服务按既定顺序处理。转派、改期
 * 是复核申请动作，实际生效后的状态分别由 {@link Action#REASSIGN} 和
 * {@link Action#RESCHEDULE} 表示。</p>
 */
public final class TaskStateMachine {
    private TaskStateMachine() {}

    public enum Phase {
        DISPATCHED, RECEIVED, FEEDBACK, ACCEPTED, ARCHIVED, WITHDRAWN;

        public static Phase parse(String value) {
            try {
                return valueOf(value);
            } catch (RuntimeException exception) {
                throw ApiError.bad("INVALID_EVENT", "不支持的任务状态");
            }
        }

        public boolean terminal() { return this == ARCHIVED || this == WITHDRAWN; }
    }

    public enum Action {
        RECEIVED, FEEDBACK, ACCEPTED, RETURNED, ARCHIVED, WITHDRAWN, REASSIGN, RESCHEDULE;

        public static Action parse(String value) {
            try {
                return valueOf(value);
            } catch (RuntimeException exception) {
                throw ApiError.bad("INVALID_EVENT", "不支持的任务事件");
            }
        }
    }

    /** PRIMARY/COLLABORATOR 只保留为历史兼容枚举；新规则只使用 PARTICIPANT。 */
    public enum Role { PARTICIPANT, ISSUER, ADMIN, OTHER, @Deprecated PRIMARY, @Deprecated COLLABORATOR }

    public enum Result { ALLOWED, FORBIDDEN, INVALID_TRANSITION }

    public record Decision(Result result, Phase next) {
        static Decision allowed(Phase next) { return new Decision(Result.ALLOWED, next); }
        static Decision forbidden() { return new Decision(Result.FORBIDDEN, null); }
        static Decision invalid() { return new Decision(Result.INVALID_TRANSITION, null); }
    }

    /**
     * 在调用者已确认任务可读后，判定其角色和当前状态是否允许该动作。
     * 角色先于状态：没有业务角色的可读上级固定收到 403，而不是借由状态泄露业务信息。
     */
    public static Decision decide(Phase phase, Action action, EnumSet<Role> roles) {
        if (!mayPerform(action, roles)) return Decision.forbidden();
        return switch (action) {
            case RECEIVED -> phase == Phase.DISPATCHED ? Decision.allowed(Phase.RECEIVED) : Decision.invalid();
            case FEEDBACK -> (phase == Phase.RECEIVED || phase == Phase.FEEDBACK) ? Decision.allowed(Phase.FEEDBACK) : Decision.invalid();
            case ACCEPTED -> phase == Phase.FEEDBACK ? Decision.allowed(Phase.ACCEPTED) : Decision.invalid();
            case RETURNED -> phase == Phase.FEEDBACK ? Decision.allowed(Phase.RECEIVED) : Decision.invalid();
            case ARCHIVED -> phase == Phase.ACCEPTED ? Decision.allowed(Phase.ARCHIVED) : Decision.invalid();
            case WITHDRAWN -> (phase == Phase.DISPATCHED || phase == Phase.RECEIVED || phase == Phase.FEEDBACK) ? Decision.allowed(Phase.WITHDRAWN) : Decision.invalid();
            case REASSIGN -> phase.terminal() ? Decision.invalid() : Decision.allowed(Phase.DISPATCHED);
            case RESCHEDULE -> phase.terminal() ? Decision.invalid() : Decision.allowed(phase);
        };
    }

    private static boolean mayPerform(Action action, EnumSet<Role> roles) {
        return switch (action) {
            case RECEIVED -> roles.contains(Role.PARTICIPANT) || roles.contains(Role.PRIMARY);
            case FEEDBACK -> roles.contains(Role.PARTICIPANT) || roles.contains(Role.PRIMARY) || roles.contains(Role.COLLABORATOR);
            case ACCEPTED, RETURNED, ARCHIVED, WITHDRAWN, REASSIGN, RESCHEDULE ->
                    roles.contains(Role.ISSUER) || roles.contains(Role.ADMIN);
        };
    }
}
