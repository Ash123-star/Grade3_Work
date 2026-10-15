package cn.workpanel;

import org.springframework.stereotype.Service;
import java.time.*;
import java.util.*;

@Service
public class Business {
    final Db db;
    public Business(Db db) { this.db=db; }
    public record Clause(String sql,List<Object> args) { public Object[] parameters() { return args.toArray(); } }
    public static Clause ownerScope(Actor a,String alias) {
        var args=new ArrayList<Object>(); args.add(a.company()); args.addAll(Arrays.asList(a.scopeArgs()));
        return new Clause(alias+".company_id=? AND EXISTS (SELECT 1 FROM users u WHERE u.id="+alias+".owner_id AND u.company_id="+alias+".company_id AND ("+a.userScope("u")+"))",args);
    }
    public static Clause taskScope(Actor a) { var s=cn.workpanel.module.task.TaskAccess.scope(a); return new Clause(s.sql(),s.args()); }
    public Map<String,Object> task(Actor a,String id,boolean lock) { return cn.workpanel.module.task.TaskAccess.readable(db,a,id,lock); }
    public Map<String,Object> log(Actor a,String id,boolean lock) {
        Clause c=ownerScope(a,"l"); var args=new ArrayList<>(c.args()); args.add(a.id()); args.add(id);
        return db.one("SELECT l.* FROM daily_logs l WHERE "+c.sql()+" AND (l.submitted OR l.owner_id=?) AND l.id=?"+(lock?" FOR UPDATE":""),args.toArray());
    }
    public static void page(int cursor,int limit) { if(cursor<0||limit<1||limit>100) throw ApiError.bad("INVALID_PAGE","cursor >= 0, limit 1–100"); }
    public static List<String> strings(Map<String,Object> m,String key) {
        Object o=m.get(key); if(o==null) return List.of(); if(!(o instanceof List<?> list)||list.size()>100||list.stream().anyMatch(x->!(x instanceof String))) throw ApiError.bad("INVALID_LIST","列表无效: "+key); return list.stream().map(Object::toString).distinct().toList();
    }
    public static void validateLog(Db db,Actor a,Map<String,Object> c) {
        Db.fields(c,"work","blockers","tomorrow","hours","taskIds"); Db.required(c,"work");
        for(String field:List.of("blockers","tomorrow")) if(c.containsKey(field)&&(!(c.get(field) instanceof String)||Db.str(c,field).length()>20000)) throw ApiError.bad("INVALID_FIELD","需要有效文本: "+field);
        if(c.containsKey("hours")) { try { double h=Double.parseDouble(c.get("hours").toString()); if(!Double.isFinite(h)||h<0||h>24) throw new NumberFormatException(); } catch(Exception e) { throw ApiError.bad("INVALID_HOURS","工时范围 0–24"); } }
        Business b=new Business(db); for(String id:strings(c,"taskIds")) b.task(a,id,false);
    }
    /** 旧调用方的列表项统一使用任务列表白名单；详情才包含正文和时间线。 */
    public static Map<String,Object> taskDto(Db db,Map<String,Object> t,boolean detail) {
        return detail?cn.workpanel.module.task.TaskView.of(db,t,cn.workpanel.module.task.TaskTimeline.list(db,Db.str(t,"id"))):cn.workpanel.module.task.TaskListView.of(t);
    }
    public static Map<String,Object> logDto(Db db,Map<String,Object> l) { var m=new LinkedHashMap<>(l); m.put("body",db.read(l.get("body"))); return m; }
    public record Range(Instant from,Instant to,LocalDate first,LocalDate end,String period) {}
    public static Range range(String date,String period) {
        LocalDate day; try { day=LocalDate.parse(date); } catch(Exception e) { throw ApiError.bad("INVALID_DATE","业务日期必须为 YYYY-MM-DD"); }
        LocalDate first=switch(period) { case "day"->day; case "week"->day.minusDays(day.getDayOfWeek().getValue()-1); case "month"->day.withDayOfMonth(1); default->throw ApiError.bad("INVALID_PERIOD","period: day/week/month"); };
        LocalDate end=switch(period) { case "day"->first.plusDays(1); case "week"->first.plusWeeks(1); default->first.plusMonths(1); };
        ZoneId zone=ZoneId.of("Asia/Shanghai"); return new Range(first.atStartOfDay(zone).toInstant(),end.atStartOfDay(zone).toInstant(),first,end,period);
    }
}
