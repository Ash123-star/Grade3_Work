package cn.workpanel.module.task;

import java.util.*;

/** 任务列表安全投影：仅包含列表契约列，绝不包含阶段、完成情况、正文或事件。 */
public final class TaskListView {
    private TaskListView() {}
    private static final List<String> COLUMNS=List.of("id","owner_id","issuer_id","title","deadline","version","created_at");

    public static Map<String,Object> of(Map<String,Object> task) {
        var result=new LinkedHashMap<String,Object>();
        for(String column:COLUMNS) result.put(column,task.get(column));
        return result;
    }
}
