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
    /**
     * 读取单篇日报并执行统一的可见性判断：本人可读自己的草稿；他人只能读取已提交内容，
     * 且必须在现有组织范围、或当前实时直属/祖先关系内。不可见统一按 404 处理，避免泄漏存在性。
     */
    public Map<String,Object> log(Actor a,String id,boolean lock) {
        var rows=db.rows("SELECT l.* FROM daily_logs l WHERE l.company_id=? AND l.id=?"+(lock?" FOR UPDATE":""),a.company(),id);
        if(rows.isEmpty()) throw ApiError.notFound();
        var log=rows.getFirst();
        if(!canReadLog(db,a,log)) throw ApiError.notFound();
        return log;
    }
    /** 实时直属/祖先关系：同公司、当前 ACTIVE，递归向上展开 reporting_relations。 */
    public static boolean reportingAncestor(Db db,Actor a,String ownerId) {
        if(ownerId==null||ownerId.isBlank()||ownerId.equals(a.id())) return false;
        return db.count("SELECT count(*) FROM users owner WHERE owner.id=? AND owner.company_id=? AND "+reportingAncestorPredicate("owner.id","owner.company_id"),ownerId,a.company(),a.id())>0;
    }
    /** 当前真实上级的统一 SQL；循环链不提供额外授权，唯一绑定参数为请求者 ID。 */
    private static String reportingAncestorPredicate(String ownerId,String companyId) {
        return "EXISTS (WITH RECURSIVE ancestors(id,path,cycle) AS ("
            +"SELECT r.manager_id,ARRAY[r.employee_id,r.manager_id],r.employee_id=r.manager_id FROM reporting_relations r JOIN users e ON e.id=r.employee_id AND e.company_id=r.company_id AND e.status='ACTIVE' JOIN users m ON m.id=r.manager_id AND m.company_id=r.company_id AND m.status='ACTIVE' WHERE r.employee_id="+ownerId+" AND r.company_id="+companyId
            +" UNION ALL SELECT r.manager_id,a.path||r.manager_id,r.manager_id=ANY(a.path) FROM reporting_relations r JOIN ancestors a ON r.employee_id=a.id JOIN users m ON m.id=r.manager_id AND m.company_id=r.company_id AND m.status='ACTIVE' WHERE r.company_id="+companyId+" AND NOT a.cycle) SELECT 1 FROM ancestors WHERE id=? AND NOT EXISTS (SELECT 1 FROM ancestors WHERE cycle))";
    }
    /**
     * 组织范围与实时直属关系的并集，是下属日志列表、成员月历和详情共用的读取判定。
     * 他人草稿永远不可读；调入调出或直属关系变更后在下次请求即生效，不使用缓存快照。
     */
    public static boolean canReadLog(Db db,Actor a,Map<String,Object> log) {
        if(log==null) return false;
        String ownerId=Db.str(log,"owner_id");
        if(a.id().equals(ownerId)) return true;
        if(!Boolean.TRUE.equals(log.get("submitted"))) return false;
        var rows=db.rows("SELECT id,company_id,department_id,team_id,status FROM users WHERE id=? AND company_id=?",ownerId,a.company());
        if(rows.isEmpty()) return false;
        return a.canSeeUser(rows.getFirst())||reportingAncestor(db,a,ownerId);
    }
    /** ownerId 过滤与下属入口的可见性判定，与详情使用同一组织范围 + 实时直属关系。 */
    public static boolean canReadUserLogs(Db db,Actor a,Map<String,Object> owner) {
        return a.canSeeUser(owner)||reportingAncestor(db,a,Db.str(owner,"id"));
    }
    /** 下属日志可见成员 SQL：现有组织范围或实时直属/祖先关系的并集，仅 ACTIVE 成员。 */
    public static Clause subordinateOwnerClause(Actor a,String alias) {
        return logOwnerClause(a,alias,true);
    }
    /** 普通日志保留原组织范围内历史成员的已提交记录，直属关系补充范围仍要求在职。 */
    public static Clause accessibleLogOwnerClause(Actor a,String alias) {
        return logOwnerClause(a,alias,false);
    }
    private static Clause logOwnerClause(Actor a,String alias,boolean activeOnly) {
        var args=new ArrayList<Object>(); args.add(a.company()); args.addAll(Arrays.asList(a.scopeArgs())); args.add(a.id());
        String scoped="EXISTS (SELECT 1 FROM users scoped_user WHERE scoped_user.id="+alias+".owner_id AND scoped_user.company_id="+alias+".company_id"+(activeOnly?" AND scoped_user.status='ACTIVE'":"")+" AND ("+a.userScope("scoped_user")+"))";
        String descendants=reportingAncestorPredicate(alias+".owner_id",alias+".company_id");
        return new Clause(alias+".company_id=? AND ("+scoped+" OR "+descendants+")",args);
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
    /** 日志按上海业务日期过滤；显式区间端点必须落在上海自然日零点。 */
    public static Range dateRange(String from,String to) {
        Instant start=parseInstant(from),finish=parseInstant(to); ZoneId zone=ZoneId.of("Asia/Shanghai");
        if(!start.isBefore(finish)) throw ApiError.bad("INVALID_RANGE","to 必须晚于 from");
        LocalDate first=start.atZone(zone).toLocalDate(),end=finish.atZone(zone).toLocalDate();
        if(!first.atStartOfDay(zone).toInstant().equals(start)||!end.atStartOfDay(zone).toInstant().equals(finish))
            throw ApiError.bad("INVALID_RANGE","日志 from/to 必须位于上海自然日零点");
        return new Range(start,finish,first,end,"range");
    }
    private static Instant parseInstant(String value) {
        try { return OffsetDateTime.parse(value).toInstant(); }
        catch(Exception ignored) { try { return Instant.parse(value); }
        catch(Exception error) { throw ApiError.bad("INVALID_RANGE","from/to 必须为带时区的 ISO-8601 时间"); } }
    }
    public static Range range(String date,String period) {
        LocalDate day; try { day=LocalDate.parse(date); } catch(Exception e) { throw ApiError.bad("INVALID_DATE","业务日期必须为 YYYY-MM-DD"); }
        LocalDate first=switch(period) { case "day"->day; case "week"->day.minusDays(day.getDayOfWeek().getValue()-1); case "month"->day.withDayOfMonth(1); default->throw ApiError.bad("INVALID_PERIOD","period: day/week/month"); };
        LocalDate end=switch(period) { case "day"->first.plusDays(1); case "week"->first.plusWeeks(1); default->first.plusMonths(1); };
        ZoneId zone=ZoneId.of("Asia/Shanghai"); return new Range(first.atStartOfDay(zone).toInstant(),end.atStartOfDay(zone).toInstant(),first,end,period);
    }
}
