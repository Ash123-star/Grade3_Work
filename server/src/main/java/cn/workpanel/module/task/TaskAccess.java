package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.*;

/** 任务读取范围：同公司内的派发人、参与人，或主负责人在请求者组织范围内。范围外统一 404。 */
public final class TaskAccess {
    private TaskAccess() {}
    public record Scope(String sql,List<Object> args) {}

    /** 别名固定为 t；与 V4 之前 Business.taskScope 的条件和参数顺序一致。 */
    public static Scope scope(Actor a) {
        var args=new ArrayList<Object>(); args.add(a.company()); args.addAll(Arrays.asList(a.scopeArgs())); args.add(a.id()); args.add(a.id());
        return new Scope("t.company_id=? AND (EXISTS (SELECT 1 FROM users u WHERE u.id=t.owner_id AND u.company_id=t.company_id AND ("+a.userScope("u")+")) OR t.issuer_id=? OR EXISTS (SELECT 1 FROM task_assignees ta WHERE ta.task_id=t.id AND ta.user_id=?))",args);
    }

    public static Map<String,Object> readable(Db db,Actor a,String id,boolean lock) {
        var s=scope(a); var args=new ArrayList<>(s.args()); args.add(id);
        var rows=db.rows("SELECT t.* FROM tasks t WHERE "+s.sql()+" AND t.id=?"+(lock?" FOR UPDATE":""),args.toArray());
        if(rows.isEmpty()) throw ApiError.notFound(); return rows.getFirst();
    }

    /** 幂等重放按派发人身份读取，不受其组织变动影响。 */
    static Map<String,Object> issued(Db db,Actor a,String id) {
        var rows=db.rows("SELECT * FROM tasks WHERE id=? AND company_id=? AND issuer_id=?",id,a.company(),a.id());
        if(rows.isEmpty()) throw ApiError.notFound(); return rows.getFirst();
    }
}
