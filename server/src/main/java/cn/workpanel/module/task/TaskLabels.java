package cn.workpanel.module.task;

import cn.workpanel.*;
import java.util.*;

/** 标签选择和投影；标签维护接口在 TaskLabelController，任务只能选择一个有效标签。 */
public final class TaskLabels {
    private TaskLabels() {}

    public static void validate(Db db,Actor actor,TaskDraft draft) {
        if(draft.labelId()==null) return;
        var rows=db.rows("SELECT * FROM task_labels WHERE id=? AND company_id=? AND status='ACTIVE'",draft.labelId(),actor.company());
        if(rows.isEmpty()) throw ApiError.bad("INVALID_LABEL","标签不存在、已停用或不在当前公司");
        String department=Db.str(rows.getFirst(),"department_id");
        if(!department.isEmpty()&&!actor.global()&&!department.equals(actor.department())) throw ApiError.forbidden();
    }

    public static void replace(Db db,Actor actor,String taskId,TaskDraft draft) {
        db.update("DELETE FROM task_label_links WHERE task_id=?",taskId);
        if(draft.labelId()!=null) db.update("INSERT INTO task_label_links(task_id,label_id,company_id) VALUES (?,?,?)",taskId,draft.labelId(),actor.company());
    }

    public static Map<String,Object> find(Db db,String taskId) {
        var rows=db.rows("SELECT l.id,l.name,l.category,l.color,l.status,l.version FROM task_label_links x JOIN task_labels l ON l.id=x.label_id WHERE x.task_id=?",taskId);
        return rows.isEmpty()?null:rows.getFirst();
    }
}
