package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.*;

/** 主负责人与协作人：同公司、在职、在派发人组织范围内；写入 task_assignees。 */
public final class TaskParticipants {
    private TaskParticipants() {}

    public static void validate(Db db,Actor a,TaskDraft d) {
        var people=new ArrayList<String>(); people.add(d.ownerId()); people.addAll(d.collaborators());
        for(String person:people) {
            var rows=db.rows("SELECT * FROM users WHERE id=? AND company_id=? AND status='ACTIVE'",person,a.company());
            if(rows.isEmpty()) throw ApiError.notFound();
            if(!a.canSeeUser(rows.getFirst())) throw ApiError.forbidden();
        }
    }

    /** 写入参与人并为每人写既有的派发提醒 outbox（投递不在本模块）。 */
    public static void assign(Db db,Actor a,String taskId,TaskDraft d) {
        db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES (?,?,'PRIMARY',?)",taskId,d.ownerId(),a.company());
        for(String c:d.collaborators()) db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES (?,?,'COLLABORATOR',?)",taskId,c,a.company());
        String hash=Db.hash(db.write(d.body()));
        var people=new ArrayList<String>(); people.add(d.ownerId()); people.addAll(d.collaborators());
        for(String p:people) db.notify(a,p,"TASK_ASSIGNED",taskId,"assigned:"+taskId+":"+p+":"+hash);
    }

    public static void replace(Db db,Actor a,String taskId,TaskDraft d) {
        db.update("DELETE FROM task_assignees WHERE task_id=?",taskId); assign(db,a,taskId,d);
    }

    public static List<String> collaborators(Db db,String taskId) {
        return db.rows("SELECT user_id FROM task_assignees WHERE task_id=? AND kind='COLLABORATOR' ORDER BY user_id",taskId).stream().map(r->Db.str(r,"user_id")).toList();
    }
}
