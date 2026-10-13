package cn.workpanel.module.task;

import cn.workpanel.Db;
import java.util.*;

/** 任务详情视图；字段与原 taskDto(detail=true) 兼容，不含完成情况字段。 */
public final class TaskView {
    private TaskView() {}
    static final List<String> COLUMNS=List.of("id","owner_id","issuer_id","title","deadline","version","created_at");

    public static Map<String,Object> of(Db db,Map<String,Object> task,List<Map<String,Object>> events) {
        var result=new LinkedHashMap<String,Object>(); for(String k:COLUMNS) result.put(k,task.get(k));
        result.put("fields",db.read(task.get("body")));
        if(events!=null) result.put("events",events);
        return result;
    }
}
