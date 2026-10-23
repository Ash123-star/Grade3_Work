package cn.workpanel.module.task;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 标签维护与范围查询；只有创始人可直接变更标签。 */
@Service
public class TaskLabelService {
    private final Db db;
    public TaskLabelService(Db db) { this.db=db; }

    public List<Map<String,Object>> list(Actor actor) {
        return db.rows("SELECT id,name,category,color,department_id,status,version,updated_at FROM task_labels WHERE company_id=? AND status='ACTIVE' AND (department_id IS NULL OR ? OR department_id=?) ORDER BY category,name,id",
                actor.company(),actor.global(),actor.department());
    }

    @Transactional public Map<String,Object> create(Actor actor,Map<String,Object> raw) {
        founder(actor); var value=normalize(raw,false); String id=Db.id();
        db.update("INSERT INTO task_labels(id,company_id,department_id,name,category,color,creator_id,status) VALUES (?,?,?,?,?,?,?,'ACTIVE')",
                id,actor.company(),value.departmentId(),value.name(),value.category(),value.color(),actor.id());
        db.audit(actor,"TASK_LABEL_CREATED",id,Map.of(),Map.of("name",value.name(),"category",value.category(),"color",value.color()),"创建任务标签");
        return get(actor,id);
    }

    @Transactional public Map<String,Object> update(Actor actor,String id,Map<String,Object> raw) {
        founder(actor); var value=normalize(raw,true); int version=Db.version(raw);
        var before=get(actor,id);
        Db.conflict(db.update("UPDATE task_labels SET department_id=?,name=?,category=?,color=?,status=?,version=version+1,updated_at=now() WHERE id=? AND company_id=? AND version=?",
                value.departmentId(),value.name(),value.category(),value.color(),value.status(),id,actor.company(),version));
        var after=get(actor,id); db.audit(actor,"TASK_LABEL_UPDATED",id,before,after,"更新任务标签"); return after;
    }

    private Map<String,Object> get(Actor actor,String id) {
        return db.one("SELECT id,name,category,color,department_id,status,version,updated_at FROM task_labels WHERE id=? AND company_id=?",id,actor.company());
    }

    private record LabelValue(String name,String category,String color,String departmentId,String status) {}
    private LabelValue normalize(Map<String,Object> raw,boolean update) {
        Db.fields(raw,update?new String[]{"name","category","color","departmentId","status","version"}:new String[]{"name","category","color","departmentId"});
        String name=Db.required(raw,"name"); String category=Db.required(raw,"category"); String color=Db.required(raw,"color");
        if(name.length()>100||category.length()>100||!color.matches("#[0-9a-fA-F]{6}")) throw ApiError.bad("INVALID_LABEL","标签名称、分类或颜色无效");
        String department=raw.containsKey("departmentId")?Db.required(raw,"departmentId"):null;
        String status=update?Db.required(raw,"status"):"ACTIVE";
        if(!Set.of("ACTIVE","DISABLED").contains(status)) throw ApiError.bad("INVALID_LABEL","标签状态无效");
        return new LabelValue(name,category,color,department,status);
    }
    private static void founder(Actor actor) { if(!"FOUNDER".equals(actor.role())) throw ApiError.forbidden(); }
}
