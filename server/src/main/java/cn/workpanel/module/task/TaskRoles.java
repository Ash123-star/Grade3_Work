package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import java.util.EnumSet;
import java.util.Map;

/** 由任务行和参与人表计算动作角色；组织数据范围不在此处转换为业务角色。 */
public final class TaskRoles {
    private TaskRoles() {}

    public static EnumSet<TaskStateMachine.Role> resolve(Db db, Actor actor, Map<String, Object> task) {
        var roles = EnumSet.noneOf(TaskStateMachine.Role.class);
        if (actor.id().equals(Db.str(task, "issuer_id"))) roles.add(TaskStateMachine.Role.ISSUER);
        if (actor.admin()) roles.add(TaskStateMachine.Role.ADMIN);
        if (db.count("SELECT count(*) FROM task_participants WHERE task_id=? AND user_id=?",
                Db.str(task, "id"), actor.id()) > 0) {
            roles.add(TaskStateMachine.Role.PARTICIPANT);
        }
        // V16 回填前或异常旧库的只读兼容：旧 owner 仅映射为参与人，不向接口泄露角色。
        if(actor.id().equals(Db.str(task,"owner_id"))) roles.add(TaskStateMachine.Role.PARTICIPANT);
        if (roles.isEmpty()) roles.add(TaskStateMachine.Role.OTHER);
        return roles;
    }
}
