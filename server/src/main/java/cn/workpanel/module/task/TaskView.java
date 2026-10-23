package cn.workpanel.module.task;

import cn.workpanel.Db;
import java.util.*;

/** 任务详情安全视图：参与人是集合，不暴露负责人、协作人或完成情况。 */
public final class TaskView {
    private TaskView() {}
    static final List<String> COLUMNS=List.of("id","issuer_id","title","start_at","deadline","version","created_at");

    public static Map<String,Object> of(Db db,Map<String,Object> task,List<Map<String,Object>> events) {
        var result=new LinkedHashMap<String,Object>(); for(String k:COLUMNS) result.put(k,task.get(k));
        result.put("fields",db.read(task.get("body")));
        result.put("participants",TaskParticipants.list(db,Db.str(task,"id")));
        result.put("label",TaskLabels.find(db,Db.str(task,"id")));
        if(events!=null) result.put("events",events);
        return result;
    }
}
