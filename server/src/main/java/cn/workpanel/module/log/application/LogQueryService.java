package cn.workpanel.module.log.application;

import cn.workpanel.*;
import org.springframework.stereotype.Service;
import java.time.*;
import java.util.*;

/** 日报列表应用服务：组织范围和草稿私密性只在服务端决定。 */
@Service
public class LogQueryService {
    final Db db; final LogQueryRepository repository;
    public LogQueryService(Db db) { this.db=db; this.repository=new LogQueryRepository(db); }
    /** period 为 null 表示调用方未显式指定；仅在旧 date 查询时回落为 day。 */
    public record Query(int cursor,int limit,String ownerId,String date,String period,String departmentId,String search,String from,String to) {
        public Query(int cursor,int limit,String ownerId,String date,String period) { this(cursor,limit,ownerId,date,period,null,null,null,null); }
        public Query(int cursor,int limit,String ownerId,String date,String period,String departmentId,String search) { this(cursor,limit,ownerId,date,period,departmentId,search,null,null); }
    }

    /**
     * 普通列表允许本人草稿；下属模式只返回当前组织范围或实时直属关系内其他成员已提交的日报。
     * from/to 必须成对、带时区且与 date/period 互斥；查询区间为左闭右开的上海业务日期。
     */
    public Map<String,Object> list(Actor actor,Query query,boolean subordinate) {
        Business.page(query.cursor(),query.limit());
        if(subordinate&&!actor.manager()) throw ApiError.forbidden();
        Business.Range range=range(query);
        if(query.search()!=null&&query.search().length()>100) throw ApiError.bad("INVALID_SEARCH","关键词最多100字");
        if(query.departmentId()!=null&&query.departmentId().length()>100) throw ApiError.bad("INVALID_DEPARTMENT","部门参数无效");
        if(query.departmentId()!=null&&query.departmentId().isBlank()) throw ApiError.bad("INVALID_DEPARTMENT","部门参数无效");
        if(query.departmentId()!=null) repository.requireDepartment(actor,query.departmentId());
        if(query.ownerId()!=null) {
            var owner=repository.owner(actor,query.ownerId());
            if(!Business.canReadUserLogs(db,actor,owner)) throw ApiError.forbidden();
            if(subordinate&&!"ACTIVE".equals(Db.str(owner,"status"))) throw ApiError.forbidden();
        }
        var page=repository.find(actor,query,subordinate,range);
        var now=java.time.Instant.now();
        var items=page.items().stream().map(log->{
            var dto=LogEditWindow.view(db,actor,log,now);
            dto.put("author",Map.of("id",Db.str(log,"owner_id"),"name",Db.str(log,"author_name")));
            dto.put("department",Map.of("id",Db.str(log,"department_id"),"name",Db.str(log,"department_name")));
            return dto;
        }).toList();
        var result=new LinkedHashMap<String,Object>();
        result.put("items",items); result.put("total",page.total()); result.put("nextCursor",String.valueOf(query.cursor()+query.limit()));
        if(subordinate) {
            var groups=new LinkedHashMap<String,Map<String,Object>>();
            for(var item:items) {
                var group=groups.computeIfAbsent(Db.str(item,"department_id"),key->{
                    var value=new LinkedHashMap<String,Object>(); value.put("department",item.get("department")); value.put("items",new ArrayList<Map<String,Object>>()); return value;
                });
                @SuppressWarnings("unchecked") var records=(List<Map<String,Object>>)group.get("items"); records.add(item);
            }
            result.put("groups",new ArrayList<>(groups.values()));
        }
        return result;
    }

    /**
     * 返回授权成员上海自然月的完整提交状态，不从分页结果推算缺交。
     * ownerId 必须在当前组织范围或实时直属/祖先关系内且为在职成员；没有可信入职日的历史日期为 UNKNOWN。
     */
    public Map<String,Object> calendar(Actor actor,String ownerId,String monthText) {
        if(!actor.manager()) throw ApiError.forbidden();
        if(ownerId==null||ownerId.isBlank()||ownerId.length()>100) throw ApiError.bad("INVALID_OWNER","ownerId 无效");
        if(monthText==null||!monthText.matches("\\d{4}-\\d{2}")) throw ApiError.bad("INVALID_MONTH","month 必须为 YYYY-MM");
        YearMonth month; try { month=YearMonth.parse(monthText); } catch(Exception error) { throw ApiError.bad("INVALID_MONTH","month 必须为有效的 YYYY-MM"); }
        var owner=repository.owner(actor,ownerId);
        if(ownerId.equals(actor.id())||!Business.canReadUserLogs(db,actor,owner)) throw ApiError.forbidden();
        if(!"ACTIVE".equals(Db.str(owner,"status"))) throw ApiError.forbidden();
        LocalDate start=month.atDay(1),end=month.atEndOfMonth();
        var submitted=repository.submittedIds(actor.company(),ownerId,start,end);
        LocalDate employment=owner.get("employment_start_date")==null?null:localDate(owner.get("employment_start_date"));
        LocalDate today=LocalDate.now(ZoneId.of("Asia/Shanghai"));
        var days=new LinkedHashMap<String,String>();
        for(LocalDate day=start;!day.isAfter(end);day=day.plusDays(1)) {
            String state;
            if(day.isAfter(today)) state="FUTURE";
            else if(submitted.containsKey(Integer.toString(day.getDayOfMonth()))) state="SUBMITTED";
            else if(employment==null||day.isBefore(employment)) state="UNKNOWN";
            else state="MISSING";
            days.put(Integer.toString(day.getDayOfMonth()),state);
        }
        var result=new LinkedHashMap<String,Object>(); result.put("ownerId",ownerId); result.put("month",month.toString());
        result.put("employmentStartDate",employment); result.put("days",days);
        result.put("logIds",submitted); return result;
    }

    /** from/to 与旧 date/period 只能二选一；显式区间必须是带时区的上海自然日边界。 */
    private static Business.Range range(Query query) {
        boolean explicit=query.from()!=null||query.to()!=null;
        if(explicit) {
            if(query.from()==null||query.to()==null) throw ApiError.bad("INVALID_RANGE","from/to 必须同时提供");
            if(query.date()!=null||query.period()!=null) throw ApiError.bad("INVALID_RANGE","from/to 不能与 date/period 同时使用");
            return Business.dateRange(query.from(),query.to());
        }
        if(query.date()==null&&query.period()!=null) throw ApiError.bad("INVALID_RANGE","period 必须与 date 一起提供");
        return query.date()==null?null:Business.range(query.date(),query.period()==null?"day":query.period());
    }

    private static LocalDate localDate(Object value) {
        if(value instanceof java.sql.Date date) return date.toLocalDate();
        if(value instanceof LocalDate date) return date;
        return LocalDate.parse(value.toString());
    }
}
