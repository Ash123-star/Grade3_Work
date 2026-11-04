package cn.workpanel.module.task;

import cn.workpanel.*;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import java.time.*;
import java.util.*;

/** 列表保持旧日期模式；日历范围读取在单个一致性快照内绑定授权、总数、顺序和版本。 */
@Service
public class TaskQueryService {
    private static final String LIST_COLUMNS="t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at,(tp.task_id IS NOT NULL) AS pinned,tp.pinned_at";
    /** 当前用户的个人置顶；只影响本人排序。 */
    private static final String PIN_JOIN=" LEFT JOIN task_pins tp ON tp.task_id=t.id AND tp.user_id=?";
    private static final String CARD_COLUMNS="t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.phase,t.version,t.created_at";
    /** 最早真实 DISPATCHED 事件时间；缺失时为 NULL，不推测。 */
    private static final String DISPATCH_LATERAL=" LEFT JOIN LATERAL (SELECT min(e.created_at) AS dispatch_at FROM task_events e WHERE e.company_id=t.company_id AND e.task_id=t.id AND e.type='DISPATCHED') dispatched ON true";
    final Db db; final ScheduleConstraints constraints; final CurrentActors actors;
    @Autowired public TaskQueryService(Db db,ScheduleConstraints constraints,CurrentActors actors) { this.db=db;this.constraints=constraints;this.actors=actors; }
    public TaskQueryService(Db db) { this(db,new ScheduleConstraints(false),null); }
    public record Query(int cursor,int limit,String search,String participantId,String date,String period,String from,String to,String snapshotToken,String ownerId) {
        public Query {
            participantId = participantId == null || participantId.isBlank() ? null : participantId.trim();
            ownerId = ownerId == null || ownerId.isBlank() ? null : ownerId.trim();
            if (participantId != null && ownerId != null && !participantId.equals(ownerId)) {
                throw ApiError.bad("INVALID_PARTICIPANT_FILTER", "ownerId 与 participantId 必须相同");
            }
            if (participantId == null) participantId = ownerId;
            ownerId = null;
        }
        public Query(int cursor,int limit,String search,String participantId,String date,String period,String from,String to) { this(cursor,limit,search,participantId,date,period,from,to,null,null); }
        public Query(int cursor,int limit,String search,String participantId,String date,String period) { this(cursor,limit,search,participantId,date,period,null,null,null,null); }
    }
    /** from/to 必须为带时区半开区间，最多 62 业务日；后页带原 token；超密度/快照变化不得截断。 */
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> list(Actor identity,Query query) {
        Business.page(query.cursor(),query.limit());
        keyword(query.search());
        if(query.date()==null && query.period()!=null && query.from()==null && query.to()==null) throw ApiError.bad("INVALID_RANGE","period 必须与 date 一起提供");
        boolean calendar=query.from()!=null||query.to()!=null;
        Actor actor=calendar&&actors!=null?actors.fresh(identity):identity;
        Business.Range range=query.date()==null?null:Business.range(query.date(),query.period()==null?"day":query.period());
        var scope=Business.taskScope(actor);var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND t.title ILIKE ?";args.add("%"+(query.search()==null?"":query.search())+"%");
        if(query.participantId()!=null) {
            validateParticipant(actor,query.participantId());
            where+=" AND EXISTS (SELECT 1 FROM task_participants p WHERE p.task_id=t.id AND p.user_id=?)";args.add(query.participantId());
        }
        if(calendar) {
            if(query.date()!=null || query.period()!=null)throw ApiError.bad("INVALID_RANGE","不能混用日历范围与旧日期筛选");
            var bounds=range(query.from(),query.to());
            where+=" AND (t.start_at IS NULL OR t.start_at<=t.deadline) AND COALESCE(t.start_at,t.deadline)<?::timestamptz AND t.deadline>=?::timestamptz";
            args.add(bounds[1].toInstant().toString());args.add(bounds[0].toInstant().toString());
            // 有界读取同时给出摘要、总数与页，避免 count/page 跨快照及旧游标的假终点。
            var calendarArgs=new ArrayList<Object>(args);calendarArgs.add(0,actor.id());
            var rows=db.rows("SELECT "+LIST_COLUMNS+",t.phase FROM tasks t"+PIN_JOIN+" WHERE "+where+" ORDER BY t.deadline,t.id LIMIT 5001",calendarArgs.toArray());
            if(rows.size()>5000)throw new ApiError(422,"CALENDAR_RANGE_TOO_DENSE","日历范围超过 5000 条，请缩小范围或使用任务列表");
            var ordered=rows.stream().map(t->List.of(t.get("id"),t.get("version"))).toList();
            String fingerprint=actors==null?actor.toString():actors.fingerprint(actor);
            String token=Db.hash(db.write(Arrays.asList("calendar-snapshot-v1",fingerprint,actor.status(),actor.mustChange(),query.search(),query.participantId(),bounds[0].toString(),bounds[1].toString(),ordered)));
            // Older published clients did not send snapshots. Preserve their
            // scoped paging; the new calendar reader requires and binds tokens.
            if(query.snapshotToken()!=null&&!query.snapshotToken().equals(token))throw new ApiError(409,"CALENDAR_SNAPSHOT_CHANGED","日历数据已变化，请整轮重读");
            if(query.cursor()>rows.size() || query.cursor()==rows.size()&&query.cursor()>0) throw ApiError.bad("INVALID_PAGE","游标超出日历范围");
            int end=(int)Math.min(rows.size(),(long)query.cursor()+query.limit());
            var items=rows.subList(query.cursor(),end).stream().map(t->project(actor,t)).toList();
            var result=new LinkedHashMap<String,Object>();result.put("items",items);result.put("total",rows.size());
            result.put("nextCursor",end<rows.size()?String.valueOf(end):null);result.put("snapshotToken",token);result.put("scheduleConstraints",constraints.view());return result;
        }
        if(range!=null) { where+=" AND (t.start_at IS NULL OR t.start_at<=t.deadline) AND COALESCE(t.start_at,t.deadline)<?::timestamptz AND t.deadline>=?::timestamptz";args.add(range.to().toString());args.add(range.from().toString()); }
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray());args.add(0,actor.id());args.add(query.limit());args.add(query.cursor());
        var items=db.rows("SELECT "+LIST_COLUMNS+",t.phase FROM tasks t"+PIN_JOIN+" WHERE "+where+" ORDER BY (tp.task_id IS NOT NULL) DESC,tp.pinned_at DESC,t.deadline,t.id LIMIT ? OFFSET ?",args.toArray()).stream().map(t->project(actor,t)).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf((long)query.cursor()+query.limit()),"scheduleConstraints",constraints.view());
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

    private Map<String,Object> project(Actor actor,Map<String,Object> task) {
        var view=TaskListView.of(db,task);view.put("capabilities",Map.of("reschedule",constraints.mayMove(actor,task)));return view;
    }
    public static OffsetDateTime[] range(String from,String to) {
        try {
            var begin=OffsetDateTime.parse(from);var end=OffsetDateTime.parse(to);
            if(!begin.isBefore(end) || Duration.between(begin,end).compareTo(Duration.ofDays(62))>0)throw new IllegalArgumentException();
            return new OffsetDateTime[]{begin.withOffsetSameInstant(ZoneOffset.UTC),end.withOffsetSameInstant(ZoneOffset.UTC)};
        } catch(RuntimeException e) {throw ApiError.bad("INVALID_RANGE","from/to 必须为有序带时区时刻，跨度不超过 62 日");}
    }
    private void validateParticipant(Actor actor,String id) {
        var user=db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,actor.company());
        if(!actor.canSeeUser(user))throw ApiError.forbidden();
    }
}
