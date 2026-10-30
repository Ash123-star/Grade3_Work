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

    /** 记录由生命周期状态机生效的事件快照；历史事件的三个快照列保持为空。 */
    public static void append(Db db,Actor a,String taskId,String type,Object body,
            String fromPhase,String toPhase,int taskVersion) {
        db.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body,from_phase,to_phase,task_version) VALUES (?,?,?,?,?::jsonb,?,?,?)",
                a.company(),taskId,a.id(),type,db.write(body),fromPhase,toPhase,taskVersion);
    }

    public static List<Map<String,Object>> list(Db db,String taskId) {
        return db.rows("SELECT e.sequence,e.actor_id,u.name AS actor_name,e.type,e.body,e.from_phase,e.to_phase,e.task_version,e.created_at FROM task_events e LEFT JOIN users u ON u.id=e.actor_id AND u.company_id=e.company_id WHERE e.task_id=? ORDER BY e.sequence",taskId);
    }
}
