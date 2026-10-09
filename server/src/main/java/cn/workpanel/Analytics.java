package cn.workpanel;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.time.*;
import java.util.*;

@RestController
@RequestMapping("/api")
public class Analytics {
    final Db db; final Tasks tasks; final Logs logs;
    Analytics(Db db,Tasks tasks,Logs logs) { this.db=db; this.tasks=tasks; this.logs=logs; }
    @GetMapping("/health") public Map<String,Object> health() { db.count("SELECT count(*) FROM companies"); return Map.of("status","UP","time",Instant.now().toString()); }
    @GetMapping("/analytics") public Map<String,Object> stats(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="week") String period) {
        Actor a=Actor.current(r); var range=Business.range(date,period); var scope=Business.taskScope(a); var args=new ArrayList<>(scope.args()); args.add(range.from().toString()); args.add(range.to().toString());
        String interval=" AND t.created_at>=?::timestamptz AND t.created_at<?::timestamptz";
        long dispatched=db.count("SELECT count(*) FROM tasks t WHERE "+scope.sql()+interval,args.toArray());
        var deadlineArgs=new ArrayList<>(scope.args()); deadlineArgs.add(range.from().toString()); deadlineArgs.add(range.to().toString());
        String due=" AND t.deadline>=?::timestamptz AND t.deadline<?::timestamptz AND t.phase<>'WITHDRAWN'";
        long dueCount=db.count("SELECT count(*) FROM tasks t WHERE "+scope.sql()+due,deadlineArgs.toArray());
        String accepted="SELECT 1 FROM task_events e WHERE e.task_id=t.id AND e.type='ACCEPTED' AND e.created_at<=t.deadline AND e.sequence>coalesce((SELECT max(re.sequence) FROM task_events re WHERE re.task_id=t.id AND re.type='REVISED'),0)";
        long ontime=db.count("SELECT count(*) FROM tasks t WHERE "+scope.sql()+due+" AND EXISTS ("+accepted+")",deadlineArgs.toArray());
        long overdue=db.count("SELECT count(*) FROM tasks t WHERE "+scope.sql()+due+" AND t.deadline<now() AND NOT EXISTS ("+accepted+")",deadlineArgs.toArray());
        var ls=Business.ownerScope(a,"l"); var la=new ArrayList<>(ls.args()); la.add(range.first().toString()); la.add(range.end().toString());
        String logWhere=ls.sql()+" AND l.submitted AND l.business_date>=?::date AND l.business_date<?::date";
        long submitted=db.count("SELECT count(*) FROM daily_logs l WHERE "+logWhere,la.toArray());
        var unreadArgs=new ArrayList<>(la); unreadArgs.add(a.id());
        long unread=db.count("SELECT count(*) FROM daily_logs l WHERE "+logWhere+" AND NOT EXISTS (SELECT 1 FROM log_reads lr WHERE lr.log_id=l.id AND lr.reader_id=?)",unreadArgs.toArray());
        var ua=new ArrayList<Object>(List.of(a.company())); ua.addAll(Arrays.asList(a.scopeArgs()));
        long people=db.count("SELECT count(*) FROM users u WHERE u.company_id=? AND u.status='ACTIVE' AND ("+a.userScope("u")+")",ua.toArray());
        LocalDate last=range.end().minusDays(1),today=LocalDate.now(ZoneId.of("Asia/Shanghai")); if(last.isAfter(today)) last=today;
        long days=Math.max(0,java.time.temporal.ChronoUnit.DAYS.between(range.first(),last.plusDays(1))); long expected=people*days;
        var distribution=db.rows("SELECT COALESCE(u.department_id,'未分配') AS department_id,count(*) AS dispatched FROM tasks t JOIN users u ON u.id=t.owner_id WHERE "+scope.sql()+interval+" GROUP BY u.department_id",args.toArray());
        return Map.of("range",range,"updatedAt",Instant.now().toString(),"dispatched",dispatched,"overdue",overdue,"onTimeAcceptance",metric(ontime,dueCount,"区间内截止且未撤回任务；按首次验收事件时间判断"),"dailySubmission",metric(submitted,expected,"当前在职范围人数 × 区间内截至今天的自然日（未配置节假日）"),"unreadLogs",unread,"departmentDistribution",distribution);
    }
    static Map<String,Object> metric(long numerator,long denominator,String definition) { return Map.of("numerator",numerator,"denominator",denominator,"rate",denominator==0?0:(double)numerator/denominator,"definition",definition); }
    @GetMapping(value="/analytics/export",produces="text/csv") public ResponseEntity<String> export(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="week") String period,@RequestParam(defaultValue="logs") String resource) {
        if(!Set.of("logs","tasks").contains(resource)) throw ApiError.bad("INVALID_RESOURCE","resource: logs/tasks");
        var lines=new StringBuilder("\ufeffid,type,title_or_date,owner_id,version\r\n"); int offset=0;
        while(true) {
            Map<String,Object> page=resource.equals("logs")?logs.list(Actor.current(r),offset,100,null,date,period,false):tasks.list(r,offset,100,"",null,date,period);
            @SuppressWarnings("unchecked") var items=(List<Map<String,Object>>)page.get("items"); if(items.isEmpty()) break;
            for(var item:items) lines.append(csv(item.get("id"))).append(',').append(resource).append(',').append(csv(item.get(resource.equals("logs")?"business_date":"title"))).append(',').append(csv(item.get("owner_id"))).append(',').append(csv(item.get("version"))).append("\r\n");
            offset+=items.size(); if(offset>=((Number)page.get("total")).longValue()) break;
            if(offset>=10000) throw ApiError.bad("EXPORT_TOO_LARGE","导出超过 10000 条，请缩小区间");
        }
        return ResponseEntity.ok().contentType(new MediaType("text","csv",java.nio.charset.StandardCharsets.UTF_8)).header(HttpHeaders.CONTENT_DISPOSITION,"attachment; filename=\""+resource+".csv\"").body(lines.toString());
    }
    static String csv(Object o) { String s=o==null?"":o.toString(); if(s.matches("^[=+@\\-\\t\\r].*")) s="'"+s; return "\""+s.replace("\"","\"\"")+"\""; }
    @GetMapping("/timeline") public Map<String,Object> timeline(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="day") String period,@RequestParam(required=false) String ownerId) { var range=Business.range(date,period); return Map.of("range",range,"logs",logs.list(Actor.current(r),0,100,ownerId,date,period,false),"tasks",tasks.list(r,0,100,"",ownerId,date,period)); }
}
