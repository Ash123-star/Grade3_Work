package cn.workpanel.module.task;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 个人任务置顶：仅影响本人列表排序，不写审计、通知或任务版本。 */
@Service
public class TaskPinService {
    static final int PIN_LIMIT=10;
    final Db db;
    public TaskPinService(Db db) { this.db=db; }

    /** 置顶本人可见任务；已置顶返回原时间。锁定本人行使并发置顶不超过上限，计数只含仍可见的任务。 */
    @Transactional
    public Map<String,Object> pin(Actor actor,String taskId) {
        requireActive(actor);
        db.one("SELECT id FROM users WHERE id=? AND company_id=? FOR UPDATE",actor.id(),actor.company());
        TaskAccess.readable(db,actor,taskId,false);
        var existing=db.rows("SELECT pinned_at FROM task_pins WHERE user_id=? AND task_id=?",actor.id(),taskId);
        if(!existing.isEmpty()) return view(taskId,existing.getFirst().get("pinned_at"));
        var scope=TaskAccess.scope(actor); var args=new ArrayList<Object>(); args.add(actor.id()); args.addAll(scope.args());
        if(db.count("SELECT count(*) FROM task_pins tp JOIN tasks t ON t.id=tp.task_id WHERE tp.user_id=? AND "+scope.sql(),args.toArray())>=PIN_LIMIT)
            throw new ApiError(409,"PIN_LIMIT","最多置顶 "+PIN_LIMIT+" 项任务");
        db.update("INSERT INTO task_pins(user_id,task_id,company_id) VALUES (?,?,?)",actor.id(),taskId,actor.company());
        return view(taskId,db.one("SELECT pinned_at FROM task_pins WHERE user_id=? AND task_id=?",actor.id(),taskId).get("pinned_at"));
    }

    /** 取消本人置顶；未置顶也返回成功。 */
    @Transactional
    public Map<String,Object> unpin(Actor actor,String taskId) {
        requireActive(actor);
        TaskAccess.readable(db,actor,taskId,false);
        db.update("DELETE FROM task_pins WHERE user_id=? AND task_id=?",actor.id(),taskId);
        var result=new LinkedHashMap<String,Object>(); result.put("taskId",taskId); result.put("pinned",false); result.put("pinnedAt",null);
        return result;
    }

    private static Map<String,Object> view(String taskId,Object pinnedAt) {
        var result=new LinkedHashMap<String,Object>(); result.put("taskId",taskId); result.put("pinned",true); result.put("pinnedAt",pinnedAt);
        return result;
    }
    private static void requireActive(Actor actor) { if(!actor.status().equals("ACTIVE")) throw ApiError.forbidden(); }
}
