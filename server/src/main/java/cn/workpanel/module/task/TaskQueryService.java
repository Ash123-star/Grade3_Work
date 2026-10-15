package cn.workpanel.module.task;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import java.util.*;

/** 任务列表应用服务：范围过滤和字段白名单在服务端完成。 */
@Service
public class TaskQueryService {
    private static final String LIST_COLUMNS="t.id,t.owner_id,t.issuer_id,t.title,t.deadline,t.version,t.created_at";
    final Db db;
    public TaskQueryService(Db db) { this.db=db; }

    /** HTTP 层已完成协议绑定后的查询参数；cursor 为非负偏移量。 */
    public record Query(int cursor,int limit,String search,String ownerId,String date,String period) {}

    /** 返回调用者范围内的任务；列表项不含生命周期、完成情况或正文。 */
    public Map<String,Object> list(Actor actor,Query query) {
        Business.page(query.cursor(),query.limit());
        Business.Range range=query.date()==null?null:Business.range(query.date(),query.period());
        var scope=Business.taskScope(actor);
        var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND t.title ILIKE ?";
        args.add("%"+(query.search()==null?"":query.search())+"%");
        if(query.ownerId()!=null) validateOwner(actor,query.ownerId());
        if(query.ownerId()!=null) { where+=" AND t.owner_id=?"; args.add(query.ownerId()); }
        if(range!=null) {
            where+=" AND t.deadline>=?::timestamptz AND t.deadline<?::timestamptz";
            args.add(range.from().toString()); args.add(range.to().toString());
        }
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray());
        args.add(query.limit()); args.add(query.cursor());
        var items=db.rows("SELECT "+LIST_COLUMNS+" FROM tasks t WHERE "+where+" ORDER BY t.deadline,t.id LIMIT ? OFFSET ?",args.toArray())
            .stream().map(TaskListView::of).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf(query.cursor()+query.limit()));
    }

    private void validateOwner(Actor actor,String ownerId) {
        var user=db.one("SELECT * FROM users WHERE id=? AND company_id=?",ownerId,actor.company());
        if(!actor.canSeeUser(user)) throw ApiError.forbidden();
    }
}
