package cn.workpanel.module.task;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.*;

/** 任务列表应用服务：组织范围、时间区间相交和字段白名单只在服务端决定。 */
@Service
public class TaskQueryService {
    private static final String LIST_COLUMNS="t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at";
    private static final String CARD_COLUMNS="t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.phase,t.version,t.created_at";
    /** 最早真实 DISPATCHED 事件时间；缺失时为 NULL，不推测。 */
    private static final String DISPATCH_LATERAL=" LEFT JOIN LATERAL (SELECT min(e.created_at) AS dispatch_at FROM task_events e WHERE e.company_id=t.company_id AND e.task_id=t.id AND e.type='DISPATCHED') dispatched ON true";
    final Db db;
    public TaskQueryService(Db db) { this.db=db; }

    /** HTTP 层已完成协议绑定后的查询参数；from/to 是带时区 ISO-8601 左闭右开网格范围。 */
    public record Query(int cursor,int limit,String search,String participantId,String date,String period,String from,String to) {
        public Query(int cursor,int limit,String search,String participantId,String date,String period) { this(cursor,limit,search,participantId,date,period,null,null); }
    }

    /**
     * 返回调用者范围内的任务；列表项不含生命周期、完成情况或正文。
     * 提供 from/to 时按任务区间 [start_at, deadline] 与查询区间 [from, to) 相交筛选，
     * start_at 为空按现有业务语义视为只占用 deadline 一个时间点；反向区间的脏数据不命中。
     */
    public Map<String,Object> list(Actor actor,Query query) {
        Business.page(query.cursor(),query.limit());
        String search=keyword(query.search());
        Instant from=null,to=null;
        if(query.from()!=null||query.to()!=null) {
            if(query.from()==null||query.to()==null||query.date()!=null||query.period()!=null)
                throw ApiError.bad("INVALID_RANGE","from/to 必须同时提供，且不能与 date/period 同时使用");
            from=instant(query.from()); to=instant(query.to());
            if(!from.isBefore(to)) throw ApiError.bad("INVALID_RANGE","to 必须晚于 from");
        } else if(query.date()!=null) {
            var range=Business.range(query.date(),query.period()==null?"day":query.period()); from=range.from(); to=range.to();
        } else if(query.period()!=null) {
            throw ApiError.bad("INVALID_RANGE","period 必须与 date 一起提供");
        }
        var scope=Business.taskScope(actor);
        var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND t.title ILIKE ?";
        args.add("%"+search+"%");
        if(query.participantId()!=null) {
            requireVisibleParticipant(actor,query.participantId());
            where+=" AND EXISTS (SELECT 1 FROM task_participants p WHERE p.task_id=t.id AND p.user_id=?)";
            args.add(query.participantId());
        }
        if(from!=null) {
            where+=" AND (t.start_at IS NULL OR t.start_at<=t.deadline) AND COALESCE(t.start_at,t.deadline)<?::timestamptz AND t.deadline>=?::timestamptz";
            args.add(to.toString()); args.add(from.toString());
        }
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray());
        args.add(query.limit()); args.add(query.cursor());
        var items=db.rows("SELECT "+LIST_COLUMNS+" FROM tasks t WHERE "+where+" ORDER BY t.deadline,t.id LIMIT ? OFFSET ?",args.toArray())
            .stream().map(task->TaskListView.of(db,task)).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf(query.cursor()+items.size()));
    }

    /**
     * 查询当前 Actor 本人参与的任务卡片历史，不按完成状态过滤，包含撤回、验收与归档记录。
     * dispatchAt 来自最早真实 DISPATCHED 事件；缺少事件时间的旧数据排在末尾，同时间按 id 稳定排序。
     * cursor 为稳定偏移分页，limit 范围 1–100；本只读 GET 不要求幂等键。
     */
    public Map<String,Object> receivedCard(Actor actor,int cursor,int limit,String search) {
        Business.page(cursor,limit);
        String keyword=keyword(search);
        var scope=Business.taskScope(actor);
        var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND EXISTS (SELECT 1 FROM task_participants personal WHERE personal.task_id=t.id AND personal.company_id=t.company_id AND personal.user_id=?) AND t.title ILIKE ?";
        args.add(actor.id());
        args.add("%"+keyword+"%");
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray());
        args.add(limit); args.add(cursor);
        var items=db.rows("SELECT "+CARD_COLUMNS+",dispatched.dispatch_at AS dispatch_at FROM tasks t"+DISPATCH_LATERAL
                +" WHERE "+where+" ORDER BY dispatched.dispatch_at DESC NULLS LAST,t.id LIMIT ? OFFSET ?",args.toArray())
            .stream().map(task->{
                var item=new LinkedHashMap<String,Object>();
                for(String column:List.of("id","issuer_id","title","start_at","deadline","version","phase","created_at")) item.put(column,task.get(column));
                item.put("dispatchAt",task.get("dispatch_at"));
                item.put("participants",TaskParticipants.list(db,Db.str(task,"id")));
                item.put("label",TaskLabels.find(db,Db.str(task,"id")));
                return item;
            }).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf(cursor+items.size()));
    }

    private static String keyword(String search) {
        if(search==null) return "";
        if(search.length()>200) throw ApiError.bad("INVALID_SEARCH","关键词最多200字");
        return search;
    }

    /** 只接受带时区的 ISO-8601 时间；本地时间或其他格式返回 400，不静默按服务器时区解释。 */
    private static Instant instant(String value) {
        try { return OffsetDateTime.parse(value).toInstant(); }
        catch(Exception ignored) { try { return Instant.parse(value); }
        catch(Exception error) { throw ApiError.bad("INVALID_RANGE","from/to 必须为带时区的 ISO-8601 时间"); } }
    }

    /** 参与人必须是本公司且在当前 Actor 组织范围内的可见成员；范围外统一拒绝。 */
    private void requireVisibleParticipant(Actor actor,String participantId) {
        var user=db.one("SELECT * FROM users WHERE id=? AND company_id=?",participantId,actor.company());
        if(!actor.canSeeUser(user)) throw ApiError.forbidden();
    }
}
