package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import java.util.*;

/** 任务事件时间线：只追加（V4 触发器禁止修改与删除），按序号读取。 */
public final class TaskTimeline {
    private TaskTimeline() {}

    public static void append(Db db,Actor a,String taskId,String type,Object body) {
        db.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body) VALUES (?,?,?,?,?::jsonb)",a.company(),taskId,a.id(),type,db.write(body));
    }

    public static List<Map<String,Object>> list(Db db,String taskId) {
        return db.rows("SELECT sequence,actor_id,type,body,created_at FROM task_events WHERE task_id=? ORDER BY sequence",taskId);
    }
}
