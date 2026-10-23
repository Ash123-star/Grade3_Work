package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.*;

/** 任务参与人：同公司、在职、在派发人组织范围内；唯一事实来源为 task_participants。 */
public final class TaskParticipants {
    private TaskParticipants() {}

    public static void validate(Db db,Actor a,TaskDraft d) {
        for(String person:d.participants()) {
            var rows=db.rows("SELECT * FROM users WHERE id=? AND company_id=? AND status='ACTIVE'",person,a.company());
            if(rows.isEmpty()) throw ApiError.notFound();
            if(!a.canSeeUser(rows.getFirst())) throw ApiError.forbidden();
        }
    }

    /** 写入无角色参与人并为每人写既有的派发提醒 outbox（投递不在本模块）。 */
    public static void assign(Db db,Actor a,String taskId,TaskDraft d) {
        String hash=Db.hash(db.write(d.body()));
        for(String p:d.participants()) {
            db.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?) ON CONFLICT (task_id,user_id) DO NOTHING",taskId,p,a.company());
            db.notify(a,p,"TASK_ASSIGNED",taskId,"assigned:"+taskId+":"+p+":"+hash);
        }
    }

    public static void replace(Db db,Actor a,String taskId,TaskDraft d) {
        db.update("DELETE FROM task_participants WHERE task_id=?",taskId); assign(db,a,taskId,d);
    }

    public static List<Map<String,Object>> list(Db db,String taskId) {
        var rows=db.rows("SELECT DISTINCT u.id,u.name,u.profile->>'avatarAttachmentId' AS avatar_id FROM users u JOIN task_participants p ON p.user_id=u.id WHERE p.task_id=? ORDER BY u.id",taskId);
        if(!rows.isEmpty()) return rows;
        // 历史数据库升级失败时的安全只读兜底；V16 正常迁移后不会使用。
        return db.rows("SELECT DISTINCT u.id,u.name,u.profile->>'avatarAttachmentId' AS avatar_id FROM users u JOIN tasks t ON t.id=? LEFT JOIN task_assignees a ON a.task_id=t.id JOIN users u ON u.id=t.owner_id OR u.id=a.user_id WHERE t.id=? ORDER BY u.id",taskId,taskId);
    }

    @Deprecated public static List<String> collaborators(Db db,String taskId) { return list(db,taskId).stream().map(r->Db.str(r,"id")).toList(); }
}
