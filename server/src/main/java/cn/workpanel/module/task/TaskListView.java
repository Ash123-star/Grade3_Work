package cn.workpanel.module.task;

import cn.workpanel.Db;
import java.util.*;

/** 任务列表安全投影：不返回阶段、完成情况、正文或历史负责人。 */
public final class TaskListView {
    private TaskListView() {}
    private static final List<String> COLUMNS=List.of("id","issuer_id","title","start_at","deadline","version","created_at");

    public static Map<String,Object> of(Map<String,Object> task) {
        var result=new LinkedHashMap<String,Object>();
        for(String column:COLUMNS) result.put(column,task.get(column));
        return result;
    }

    public static Map<String,Object> of(Db db,Map<String,Object> task) {
        var result=of(task); String id=Db.str(task,"id");
        result.put("participants",TaskParticipants.list(db,id)); result.put("label",TaskLabels.find(db,id)); return result;
    }
}
