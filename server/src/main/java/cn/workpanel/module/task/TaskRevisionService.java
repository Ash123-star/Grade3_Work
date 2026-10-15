package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import org.springframework.stereotype.Service;
import java.time.OffsetDateTime;
import java.util.*;

/** 已通过复核的任务修订生效逻辑；复核编排仍由 review 模块负责。 */
@Service
public class TaskRevisionService {
    final Db db;
    public TaskRevisionService(Db db) { this.db = db; }

    /** 已完成读取范围、角色、版本和状态校验的专用复核申请。 */
    public record ReviewRequest(int version, Map<String, Object> before, Map<String, Object> candidate) {}

    /** 校验转派申请，但不修改任务；实际生效仅发生在复核通过后。 */
    public ReviewRequest prepareReassignment(Actor actor, String taskId, Map<String, Object> request) {
        var task = TaskAccess.readable(db, actor, taskId, true);
        Db.fields(request, "ownerId", "version", "reason");
        Db.required(request, "reason");
        String ownerId = Db.required(request, "ownerId");
        int version = Db.version(request);
        authorizeDedicated(actor, task, TaskStateMachine.Action.REASSIGN, version);
        if (ownerId.equals(Db.str(task, "owner_id"))) throw ApiError.bad("SAME_OWNER", "新负责人不能与当前负责人相同");
        var users = db.rows("SELECT * FROM users WHERE id=? AND company_id=? AND status='ACTIVE'", ownerId, actor.company());
        if (users.isEmpty()) throw ApiError.notFound();
        if (!actor.canSeeUser(users.getFirst())) throw ApiError.forbidden();
        return new ReviewRequest(version, Map.of("ownerId", Db.str(task, "owner_id")), Map.of("ownerId", ownerId));
    }

    /** 校验改期申请；截止时间必须为带时区且与当前截止时间实际时刻不同。 */
    public ReviewRequest prepareReschedule(Actor actor, String taskId, Map<String, Object> request) {
        var task = TaskAccess.readable(db, actor, taskId, true);
        Db.fields(request, "deadline", "version", "reason");
        Db.required(request, "reason");
        String deadline = Db.required(request, "deadline");
        try { OffsetDateTime.parse(deadline); } catch (RuntimeException exception) {
            throw ApiError.bad("INVALID_DATE", "deadline 必须带时区");
        }
        int version = Db.version(request);
        authorizeDedicated(actor, task, TaskStateMachine.Action.RESCHEDULE, version);
        String oldDeadline = Db.str(db.read(task.get("body")), "deadline");
        if (sameDeadline(oldDeadline, deadline)) throw ApiError.bad("INVALID_DEADLINE", "新截止时间不能与当前截止时间相同");
        return new ReviewRequest(version, Map.of("deadline", oldDeadline), Map.of("deadline", deadline));
    }

    private void authorizeDedicated(Actor actor, Map<String, Object> task, TaskStateMachine.Action action, int requestedVersion) {
        var phase = TaskStateMachine.Phase.parse(Db.str(task, "phase"));
        var decision = TaskStateMachine.decide(phase, action, TaskRoles.resolve(db, actor, task));
        if (decision.result() == TaskStateMachine.Result.FORBIDDEN) throw ApiError.forbidden();
        int currentVersion;
        try { currentVersion = Integer.parseInt(Db.str(task, "version")); }
        catch (NumberFormatException exception) { throw new IllegalStateException("任务版本无效", exception); }
        if (requestedVersion != currentVersion) throw ApiError.conflict();
        if (decision.result() == TaskStateMachine.Result.INVALID_TRANSITION) {
            throw new ApiError(409, "INVALID_TRANSITION", "当前任务状态不允许该动作");
        }
    }

    /** 通用修订不得借道修改负责人或截止时间，二者须经过专用复核。 */
    public Map<String, Object> validateGeneric(Db db, Actor actor, Map<String, Object> task,
            Map<String, Object> candidate) {
        var normalized = TaskRevisionSupport.validate(db, actor, Db.str(task, "id"), candidate);
        var current = db.read(task.get("body"));
        if (!Db.str(current, "ownerId").equals(Db.str(normalized, "ownerId"))
                || !sameDeadline(Db.str(current, "deadline"), Db.str(normalized, "deadline"))) {
            throw ApiError.bad("USE_DEDICATED_REVISION", "负责人和截止时间须通过转派或改期申请修改");
        }
        return normalized;
    }

    /** 应用已经通过的通用修订，保持当前生命周期状态。调用方必须已锁定任务。 */
    public void applyGeneric(Db db, Actor applicant, Map<String, Object> task, int expectedVersion,
            Map<String, Object> candidate) {
        var normalized = validateGeneric(db, applicant, task, candidate);
        var draft = TaskRevisionSupport.apply(db, applicant, Db.str(task, "id"), normalized);
        int nextVersion = expectedVersion + 1;
        Db.conflict(db.update("UPDATE tasks SET title=?,body=?::jsonb,version=? WHERE id=? AND version=?",
                draft.title(), db.write(draft.body()), nextVersion, Db.str(task, "id"), expectedVersion));
        String phase = Db.str(task, "phase");
        TaskTimeline.append(db, applicant, Db.str(task, "id"), "REVISED", draft.body(), phase, phase, nextVersion);
        notifyParticipants(db, applicant, Db.str(task, "id"), nextVersion, "TASK_REVISED");
    }

    /** 应用已通过的转派：旧主负责人移出参与人，新负责人转为唯一主负责人并回到待接收。 */
    public void applyReassignment(Db db, Actor applicant, Map<String, Object> task, int expectedVersion,
            Map<String, Object> candidate, String reason) {
        String taskId = Db.str(task, "id"), oldOwner = Db.str(task, "owner_id"), newOwner = Db.required(candidate, "ownerId");
        requireNotTerminal(task);
        if (oldOwner.equals(newOwner)) throw ApiError.bad("SAME_OWNER", "新负责人不能与当前负责人相同");
        ensureActiveOwner(db, applicant, newOwner);
        var body = new LinkedHashMap<>(db.read(task.get("body")));
        body.put("ownerId", newOwner);
        var collaborators = new ArrayList<String>();
        Object rawCollaborators = body.get("collaborators");
        if (rawCollaborators instanceof List<?> list) for (Object value : list) {
            String collaborator = String.valueOf(value);
            if (!collaborator.equals(oldOwner) && !collaborator.equals(newOwner)) collaborators.add(collaborator);
        }
        body.put("collaborators", collaborators.stream().distinct().sorted().toList());
        int nextVersion = expectedVersion + 1;
        Db.conflict(db.update("UPDATE tasks SET owner_id=?,body=?::jsonb,phase='DISPATCHED',version=? WHERE id=? AND version=?",
                newOwner, db.write(body), nextVersion, taskId, expectedVersion));
        db.update("DELETE FROM task_assignees WHERE task_id=? AND user_id IN (?,?)", taskId, oldOwner, newOwner);
        db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES (?,?,'PRIMARY',?)",
                taskId, newOwner, applicant.company());
        TaskTimeline.append(db, applicant, taskId, "REASSIGNED", Map.of("oldOwnerId", oldOwner, "ownerId", newOwner, "reason", reason),
                Db.str(task, "phase"), TaskStateMachine.Phase.DISPATCHED.name(), nextVersion);
        notifyParticipants(db, applicant, taskId, nextVersion, "TASK_REASSIGNED");
    }

    /** 应用已通过的改期：状态不变，只更新截止时间、版本和时间线。 */
    public void applyReschedule(Db db, Actor applicant, Map<String, Object> task, int expectedVersion,
            Map<String, Object> candidate, String reason) {
        String taskId = Db.str(task, "id"), deadline = Db.required(candidate, "deadline");
        requireNotTerminal(task);
        var body = new LinkedHashMap<>(db.read(task.get("body")));
        String oldDeadline = Db.str(body, "deadline");
        body.put("deadline", deadline);
        int nextVersion = expectedVersion + 1;
        Db.conflict(db.update("UPDATE tasks SET deadline=?::timestamptz,body=?::jsonb,version=? WHERE id=? AND version=?",
                deadline, db.write(body), nextVersion, taskId, expectedVersion));
        String phase = Db.str(task, "phase");
        TaskTimeline.append(db, applicant, taskId, "RESCHEDULED", Map.of("oldDeadline", oldDeadline, "deadline", deadline, "reason", reason),
                phase, phase, nextVersion);
        notifyParticipants(db, applicant, taskId, nextVersion, "TASK_RESCHEDULED");
    }

    public static boolean sameDeadline(String first, String second) {
        try {
            return OffsetDateTime.parse(first).toInstant().equals(OffsetDateTime.parse(second).toInstant());
        } catch (RuntimeException exception) {
            return first.equals(second);
        }
    }

    private static void requireNotTerminal(Map<String, Object> task) {
        if (TaskStateMachine.Phase.parse(Db.str(task, "phase")).terminal()) {
            throw new ApiError(409, "INVALID_TRANSITION", "终态任务不能修改");
        }
    }

    private static void ensureActiveOwner(Db db, Actor actor, String ownerId) {
        var users = db.rows("SELECT * FROM users WHERE id=? AND company_id=? AND status='ACTIVE'", ownerId, actor.company());
        if (users.isEmpty()) throw ApiError.notFound();
        if (!actor.canSeeUser(users.getFirst())) throw ApiError.forbidden();
    }

    private static void notifyParticipants(Db db, Actor actor, String taskId, int version, String type) {
        var recipients = new LinkedHashSet<String>();
        recipients.add(Db.str(db.one("SELECT issuer_id FROM tasks WHERE id=? AND company_id=?", taskId, actor.company()), "issuer_id"));
        for (var participant : db.rows("SELECT user_id FROM task_assignees WHERE task_id=?", taskId)) recipients.add(Db.str(participant, "user_id"));
        for (String recipient : recipients) db.notify(actor, recipient, type, taskId,
                type.toLowerCase(Locale.ROOT) + ":" + taskId + ":" + version + ":" + recipient);
    }
}
