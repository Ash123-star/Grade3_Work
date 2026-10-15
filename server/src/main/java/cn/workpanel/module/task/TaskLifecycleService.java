package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 任务生命周期用例：按读取范围、格式、角色、版本、状态的顺序执行，并在一个事务中落库。 */
@Service
public class TaskLifecycleService {
    final Db db;

    public TaskLifecycleService(Db db) { this.db = db; }

    /**
     * 生效接收、反馈、验收、退回、归档或撤回动作。
     * 请求仅接受 type、version、text；反馈、退回和撤回的说明为 1–2000 字。
     */
    @Transactional
    public Map<String, Object> apply(Actor actor, String taskId, Map<String, Object> request) {
        // 先按范围锁定目标，避免范围外调用者从格式或状态错误中获知任务信息。
        var task = TaskAccess.readable(db, actor, taskId, true);
        Db.fields(request, "type", "version", "text");
        var action = TaskStateMachine.Action.parse(Db.required(request, "type"));
        if (action == TaskStateMachine.Action.REASSIGN || action == TaskStateMachine.Action.RESCHEDULE) {
            throw ApiError.bad("INVALID_EVENT", "转派和改期必须提交复核申请");
        }
        int requestedVersion = Db.version(request);
        String text = validateText(action, request);

        var phase = TaskStateMachine.Phase.parse(Db.str(task, "phase"));
        var roles = TaskRoles.resolve(db, actor, task);
        // decide 的首个分支仅依赖角色；在版本比较前保持“角色优先”语义。
        if (TaskStateMachine.decide(phase, action, roles).result() == TaskStateMachine.Result.FORBIDDEN) {
            throw ApiError.forbidden();
        }
        int currentVersion = parseVersion(task);
        if (requestedVersion != currentVersion) throw ApiError.conflict();
        var decision = TaskStateMachine.decide(phase, action, roles);
        if (decision.result() == TaskStateMachine.Result.INVALID_TRANSITION) {
            throw new ApiError(409, "INVALID_TRANSITION", "当前任务状态不允许该动作");
        }

        int nextVersion = currentVersion + 1;
        Db.conflict(db.update("UPDATE tasks SET phase=?,version=? WHERE id=? AND version=?",
                decision.next().name(), nextVersion, taskId, currentVersion));
        var eventBody = new LinkedHashMap<String, Object>();
        if (text != null) eventBody.put("text", text);
        TaskTimeline.append(db, actor, taskId, action.name(), eventBody,
                phase.name(), decision.next().name(), nextVersion);
        db.audit(actor, "TASK_EVENT", taskId, Map.of("phase", phase.name(), "version", currentVersion),
                Map.of("phase", decision.next().name(), "version", nextVersion, "type", action.name()), text == null ? "" : text);
        notifyParticipants(actor, taskId, nextVersion);
        return TaskView.of(db, TaskAccess.readable(db, actor, taskId, false), TaskTimeline.list(db, taskId));
    }

    private static int parseVersion(Map<String, Object> task) {
        try {
            return Integer.parseInt(Db.str(task, "version"));
        } catch (NumberFormatException exception) {
            throw new IllegalStateException("任务版本无效", exception);
        }
    }

    private static String validateText(TaskStateMachine.Action action, Map<String, Object> request) {
        if (!Set.of(TaskStateMachine.Action.FEEDBACK, TaskStateMachine.Action.RETURNED,
                TaskStateMachine.Action.WITHDRAWN).contains(action)) return null;
        String text = Db.required(request, "text");
        if (text.length() > 2000) throw ApiError.bad("INVALID_FIELD", "说明长度必须为 1–2000 字");
        return text;
    }

    private void notifyParticipants(Actor actor, String taskId, int version) {
        var recipients = new LinkedHashSet<String>();
        var task = db.one("SELECT issuer_id FROM tasks WHERE id=? AND company_id=?", taskId, actor.company());
        recipients.add(Db.str(task, "issuer_id"));
        for (var participant : db.rows("SELECT user_id FROM task_assignees WHERE task_id=?", taskId)) {
            recipients.add(Db.str(participant, "user_id"));
        }
        for (String recipient : recipients) {
            db.notify(actor, recipient, "TASK_EVENT", taskId, "task-event:" + taskId + ":" + version + ":" + recipient);
        }
    }
}
