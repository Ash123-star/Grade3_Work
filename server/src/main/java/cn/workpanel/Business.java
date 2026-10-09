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
    public static Clause taskScope(Actor a) {
        var c=ownerScope(a,"t"); var args=new ArrayList<>(c.args()); args.add(a.id()); args.add(a.id());
        return new Clause("t.company_id=? AND ("+c.sql().substring(c.sql().indexOf(" AND ")+5)+" OR t.issuer_id=? OR EXISTS (SELECT 1 FROM task_assignees ta WHERE ta.task_id=t.id AND ta.user_id=?))",args);
    }
    public Map<String,Object> task(Actor a,String id,boolean lock) {
        Clause c=taskScope(a); var args=new ArrayList<>(c.args()); args.add(id);
        return db.one("SELECT t.* FROM tasks t WHERE "+c.sql()+" AND t.id=?"+(lock?" FOR UPDATE":""),args.toArray());
    }
    public Map<String,Object> log(Actor a,String id,boolean lock) {
        Clause c=ownerScope(a,"l"); var args=new ArrayList<>(c.args()); args.add(a.id()); args.add(id);
        return db.one("SELECT l.* FROM daily_logs l WHERE "+c.sql()+" AND (l.submitted OR l.owner_id=?) AND l.id=?"+(lock?" FOR UPDATE":""),args.toArray());
    }
    public static void page(int cursor,int limit) { if(cursor<0||limit<1||limit>100) throw ApiError.bad("INVALID_PAGE","cursor >= 0, limit 1–100"); }
    public static List<String> strings(Map<String,Object> m,String key) {
        Object o=m.get(key); if(o==null) return List.of(); if(!(o instanceof List<?> list)||list.size()>100||list.stream().anyMatch(x->!(x instanceof String))) throw ApiError.bad("INVALID_LIST","列表无效: "+key); return list.stream().map(Object::toString).distinct().toList();
    }
    public static void validateTask(Db db,Actor a,Map<String,Object> c) {
        c.putIfAbsent("urgency","NORMAL");
        Db.fields(c,"title","ownerId","deadline","group","content","urgency","progressNote","collaborators","attachments"); a.requireDispatch();
        String title=Db.required(c,"title"); if(title.length()>200) throw ApiError.bad("TITLE_LENGTH","标题过长");
        for(String field:List.of("group","content","progressNote")) if(c.containsKey(field)&&(!(c.get(field) instanceof String)||Db.str(c,field).length()>20000)) throw ApiError.bad("INVALID_FIELD","需要有效文本: "+field);
        try { OffsetDateTime.parse(Db.required(c,"deadline")); } catch(DateTimeException e) { throw ApiError.bad("INVALID_DATE","deadline 必须带时区"); }
        if(!Set.of("URGENT","NORMAL","LOW").contains(Db.str(c,"urgency"))) throw ApiError.bad("INVALID_URGENCY","urgency: URGENT/NORMAL/LOW");
        var people=new ArrayList<>(strings(c,"collaborators")); people.add(Db.required(c,"ownerId"));
        for(String person:people) { var user=db.one("SELECT * FROM users WHERE id=? AND company_id=? AND status='ACTIVE'",person,a.company()); if(!a.canSeeUser(user)) throw ApiError.forbidden(); }
        for(String attachment:strings(c,"attachments")) {
            var file=db.one("SELECT owner_id,task_id FROM attachments WHERE id=? AND company_id=?",attachment,a.company());
            if(!a.id().equals(file.get("owner_id"))) {
                if(file.get("task_id")==null) throw ApiError.forbidden();
                var task=new Business(db).task(a,Db.str(file,"task_id"),false);
                if(!strings(db.read(task.get("body")),"attachments").contains(attachment)) throw ApiError.forbidden();
            }
        }
    }
    public static void assign(Db db,Actor a,String id,Map<String,Object> c) {
        db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES (?,?,'PRIMARY',?)",id,c.get("ownerId"),a.company());
        for(String collaborator:strings(c,"collaborators")) if(!collaborator.equals(c.get("ownerId"))) db.update("INSERT INTO task_assignees(task_id,user_id,kind,company_id) VALUES (?,?,'COLLABORATOR',?)",id,collaborator,a.company());
        for(String attachment:strings(c,"attachments")) { var f=db.one("SELECT task_id FROM attachments WHERE id=? FOR UPDATE",attachment); if(f.get("task_id")!=null&&!f.get("task_id").equals(id)) throw ApiError.conflict(); db.update("UPDATE attachments SET task_id=? WHERE id=?",id,attachment); }
        for(var person:db.rows("SELECT user_id FROM task_assignees WHERE task_id=?",id)) db.notify(a,Db.str(person,"user_id"),"TASK_ASSIGNED",id,"assigned:"+id+":"+person.get("user_id")+":"+Db.hash(db.write(c)));
    }
    public static void validateLog(Db db,Actor a,Map<String,Object> c) {
        Db.fields(c,"work","blockers","tomorrow","hours","taskIds"); Db.required(c,"work");
        for(String field:List.of("blockers","tomorrow")) if(c.containsKey(field)&&(!(c.get(field) instanceof String)||Db.str(c,field).length()>20000)) throw ApiError.bad("INVALID_FIELD","需要有效文本: "+field);
        if(c.containsKey("hours")) { try { double h=Double.parseDouble(c.get("hours").toString()); if(!Double.isFinite(h)||h<0||h>24) throw new NumberFormatException(); } catch(Exception e) { throw ApiError.bad("INVALID_HOURS","工时范围 0–24"); } }
        Business b=new Business(db); for(String id:strings(c,"taskIds")) b.task(a,id,false);
    }
    public static Map<String,Object> taskDto(Db db,Map<String,Object> t,boolean detail) {
        var result=new LinkedHashMap<String,Object>(); for(String k:List.of("id","owner_id","issuer_id","title","deadline","version","created_at")) result.put(k,t.get(k)); result.put("fields",db.read(t.get("body")));
        if(detail) result.put("events",db.rows("SELECT sequence,actor_id,type,body,created_at FROM task_events WHERE task_id=? ORDER BY sequence",t.get("id")));
        return result;
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
