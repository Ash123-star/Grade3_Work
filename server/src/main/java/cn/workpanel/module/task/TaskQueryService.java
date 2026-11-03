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
    private static final String LIST_COLUMNS="t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at";
    final Db db; final ScheduleConstraints constraints; final CurrentActors actors;
    @Autowired public TaskQueryService(Db db,ScheduleConstraints constraints,CurrentActors actors) { this.db=db;this.constraints=constraints;this.actors=actors; }
    public TaskQueryService(Db db) { this(db,new ScheduleConstraints(false),null); }
    public record Query(int cursor,int limit,String search,String participantId,String date,String period,String from,String to,String snapshotToken,String ownerId) {
        public Query(int cursor,int limit,String search,String participantId,String date,String period) { this(cursor,limit,search,participantId,date,period,null,null,null,null); }
    }
    /** from/to 必须为带时区半开区间，最多 62 业务日；后页带原 token；超密度/快照变化不得截断。 */
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> list(Actor identity,Query query) {
        Business.page(query.cursor(),query.limit());
        boolean calendar=query.from()!=null||query.to()!=null;
        Actor actor=calendar&&actors!=null?actors.fresh(identity):identity;
        if(query.ownerId()!=null)throw ApiError.bad("UNSUPPORTED_FILTER","请使用受授权的 participantId 筛选");
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
            where+=" AND COALESCE(t.start_at,t.deadline)<?::timestamptz AND t.deadline>=?::timestamptz";
            args.add(bounds[1].toString());args.add(bounds[0].toString());
            // 有界读取同时给出摘要、总数与页，避免 count/page 跨快照及旧游标的假终点。
            var rows=db.rows("SELECT "+LIST_COLUMNS+",t.phase FROM tasks t WHERE "+where+" ORDER BY t.deadline,t.id LIMIT 5001",args.toArray());
            if(rows.size()>5000)throw new ApiError(422,"CALENDAR_RANGE_TOO_DENSE","日历范围超过 5000 条，请缩小范围或使用任务列表");
            var ordered=rows.stream().map(t->List.of(t.get("id"),t.get("version"))).toList();
            String fingerprint=actors==null?actor.toString():actors.fingerprint(actor);
            String token=Db.hash(db.write(Arrays.asList("calendar-snapshot-v1",fingerprint,actor.status(),actor.mustChange(),query.search(),query.participantId(),bounds[0].toString(),bounds[1].toString(),ordered)));
            if(query.cursor()>0 && (query.snapshotToken()==null||query.snapshotToken().isBlank())) throw ApiError.bad("INVALID_SNAPSHOT","后续页需要快照令牌");
            if(query.snapshotToken()!=null&&!query.snapshotToken().equals(token))throw new ApiError(409,"CALENDAR_SNAPSHOT_CHANGED","日历数据已变化，请整轮重读");
            if(query.cursor()>rows.size() || query.cursor()==rows.size()&&query.cursor()>0) throw ApiError.bad("INVALID_PAGE","游标超出日历范围");
            int end=(int)Math.min(rows.size(),(long)query.cursor()+query.limit());
            var items=rows.subList(query.cursor(),end).stream().map(t->project(actor,t)).toList();
            var result=new LinkedHashMap<String,Object>();result.put("items",items);result.put("total",rows.size());
            result.put("nextCursor",end<rows.size()?String.valueOf(end):null);result.put("snapshotToken",token);result.put("scheduleConstraints",constraints.view());return result;
        }
        if(range!=null) { where+=" AND t.deadline>=?::timestamptz AND t.deadline<?::timestamptz";args.add(range.from().toString());args.add(range.to().toString()); }
        long total=db.count("SELECT count(*) FROM tasks t WHERE "+where,args.toArray());args.add(query.limit());args.add(query.cursor());
        var items=db.rows("SELECT "+LIST_COLUMNS+",t.phase FROM tasks t WHERE "+where+" ORDER BY t.deadline,t.id LIMIT ? OFFSET ?",args.toArray()).stream().map(t->project(actor,t)).toList();
        return Map.of("items",items,"total",total,"nextCursor",String.valueOf((long)query.cursor()+query.limit()),"scheduleConstraints",constraints.view());
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
