package cn.workpanel.module.analytics.application;

import cn.workpanel.*;
import cn.workpanel.module.analytics.infrastructure.AnalyticsRepository;
import cn.workpanel.module.task.TaskQueryService;
import cn.workpanel.module.log.application.LogQueryService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.*;
import java.time.*;
import java.util.*;

/** 统计、钻取和导出使用同一个查询对象、权限检查和事件事实来源。 */
@Service
public class AnalyticsService {
    private static final List<String> METRICS=List.of("dispatched","received","feedback","accepted","overdue","diarySubmitted","onTimeAcceptance");
    private static final Map<String,String> PHASES=Map.of("DISPATCHED","待接收","RECEIVED","进行中","FEEDBACK","待验收","ACCEPTED","已验收","ARCHIVED","已归档","WITHDRAWN","已撤回","NEEDS_CHANGES","需补充");
    private final AnalyticsRepository repository;
    private final TaskQueryService tasks;
    private final LogQueryService logs;
    public AnalyticsService(AnalyticsRepository repository,TaskQueryService tasks,LogQueryService logs) { this.repository=repository; this.tasks=tasks; this.logs=logs; }
    public Map<String,Object> health() { repository.healthy(); return Map.of("status","UP","time",Instant.now().toString()); }

    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> statistics(Actor actor,AnalyticsQuery query) {
        repository.authorize(actor,query,null);
        var source=repository.facts(actor,query); var counts=repository.counts(source);
        var totals=emptyCounts(); var groups=new TreeMap<String,Map<String,Object>>(); var trend=new TreeMap<String,Map<String,Object>>();
        for(var row:counts) {
            String group=Db.str(row,"group_id"),bucket=Db.str(row,"bucket"),metric=Db.str(row,"metric"); long value=((Number)row.get("value")).longValue();
            totals.put(metric,totals.get(metric)+value);
            var g=groups.computeIfAbsent(group,key->{ var item=new LinkedHashMap<String,Object>(emptyCounts()); item.put("groupId",key); item.put("groupName",row.get("group_name")); return item; });
            g.put(metric,((Number)g.get(metric)).longValue()+value);
            var day=trend.computeIfAbsent(bucket,key->{ var item=new LinkedHashMap<String,Object>(emptyCounts()); item.put("date",key); return item; });
            day.put(metric,((Number)day.get(metric)).longValue()+value);
        }
        var people=repository.people(actor,query); LocalDate today=LocalDate.now(ZoneId.of("Asia/Shanghai"));
        var uncertain=repository.uncertainDiary(source);
        var uncertainGroups=new HashSet<String>(); var uncertainDays=new HashSet<String>();
        for(var row:uncertain) { uncertainGroups.add(Db.str(row,"group_id")); uncertainDays.add(Db.str(row,"bucket")); }
        var range=query.range(); long denominator=0; boolean known=uncertain.isEmpty();
        for(var person:people) {
            if(person.get("employment_start_date")==null) { known=false; continue; }
            LocalDate hired=LocalDate.parse(person.get("employment_start_date").toString());
            LocalDate first=hired.isAfter(range.first())?hired:range.first(); LocalDate end=today.plusDays(1).isBefore(range.end())?today.plusDays(1):range.end();
            denominator+=Math.max(0,java.time.temporal.ChronoUnit.DAYS.between(first,end));
        }
        for(LocalDate day=range.first();day.isBefore(range.end());day=day.plusDays(1)) {
            if(counts.isEmpty()) break;
            var point=trend.computeIfAbsent(day.toString(),key->{ var item=new LinkedHashMap<String,Object>(emptyCounts()); item.put("date",key); return item; });
            long eligible=0; boolean dayKnown=!uncertainDays.contains(day.toString());
            for(var person:people) {
                if(person.get("employment_start_date")==null) { dayKnown=false; continue; }
                if(!day.isAfter(today)&&!day.isBefore(LocalDate.parse(person.get("employment_start_date").toString()))) eligible++;
            }
            point.put("diaryDenominator",eligible); point.put("diaryDenominatorKnown",dayKnown); point.put("diaryRate",!dayKnown||eligible==0?null:((Number)point.get("diarySubmitted")).doubleValue()/eligible);
        }
        for(var group:groups.values()) {
            long groupDenominator=0; boolean groupKnown=!uncertainGroups.contains(Db.str(group,"groupId"));
            for(var person:people) {
                if(!Objects.equals(person.get("group_id"),group.get("groupId"))) continue;
                if(person.get("employment_start_date")==null) { groupKnown=false; continue; }
                LocalDate hired=LocalDate.parse(person.get("employment_start_date").toString());
                LocalDate first=hired.isAfter(range.first())?hired:range.first(); LocalDate end=today.plusDays(1).isBefore(range.end())?today.plusDays(1):range.end();
                groupDenominator+=Math.max(0,java.time.temporal.ChronoUnit.DAYS.between(first,end));
            }
            long accepted=((Number)group.get("accepted")).longValue(),onTime=((Number)group.get("onTimeAcceptance")).longValue();
            group.put("onTimeAccepted",onTime); group.put("onTimeDenominator",accepted); group.put("onTimeRate",accepted==0?null:(double)onTime/accepted);
            group.put("diaryDenominator",groupDenominator); group.put("diaryDenominatorKnown",groupKnown);
            group.put("diaryRate",!groupKnown||groupDenominator==0?null:((Number)group.get("diarySubmitted")).doubleValue()/groupDenominator);
        }
        var result=new LinkedHashMap<String,Object>(); result.putAll(totals);
        result.put("range",range); result.put("updatedAt",Instant.now()); result.put("filters",query.view()); result.put("groupBy",query.groupBy());
        result.put("onTimeAcceptance",metric(totals.get("onTimeAcceptance"),totals.get("accepted"),true,"区间内首次实际验收任务中，最新REVISED之后仍有验收且该有效验收不晚于当前截止时间的比例；组织和截止时间采用当前值"));
        result.put("dailySubmission",metric(totals.get("diarySubmitted"),denominator,known,"当前授权在职成员入职日起至今天的区间自然人数日；任一成员入职日未知时 rate 为 null，不推测历史在职人数"));
        result.put("groupedComparison",new ArrayList<>(groups.values())); result.put("departmentComparison",new ArrayList<>(groups.values()));
        result.put("trend",new ArrayList<>(trend.values())); result.put("dailyTrend",new ArrayList<>(trend.values()));
        var phases=repository.phases(source).stream().map(row->{var item=new LinkedHashMap<String,Object>(row); String phase=Db.str(row,"phase"); item.put("phase",PHASES.getOrDefault(phase,phase)); item.put("phaseCode",phase); return item;}).toList();
        result.put("taskPhaseDistribution",phases); result.put("departmentDistribution",new ArrayList<>(groups.values()));
        result.put("definition","每种阶段指标按任务首次真实事件时间计数；阶段分布为区间内真实派发任务的当前阶段，趋势不回推历史快照；组织分组按当前负责人归属");
        return result;
    }
    private static LinkedHashMap<String,Long> emptyCounts() { var value=new LinkedHashMap<String,Long>(); for(String metric:METRICS) value.put(metric,0L); return value; }
    private static Map<String,Object> metric(long numerator,long denominator,boolean known,String definition) {
        var result=new LinkedHashMap<String,Object>(); result.put("numerator",numerator); result.put("denominator",denominator); result.put("denominatorKnown",known);
        result.put("rate",!known||denominator==0?null:(double)numerator/denominator); result.put("definition",definition); return result;
    }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public Map<String,Object> details(Actor actor,AnalyticsQuery query,String metric,String groupId,String bucket,int cursor,int limit) {
        Business.page(cursor,limit); repository.authorize(actor,query,groupId); LocalDate day=query.bucket(bucket);
        String phase=null,canonical=metric;
        if(metric!=null&&metric.startsWith("phase:")) {
            String value=metric.substring(6);
            phase=PHASES.containsKey(value)?value:PHASES.entrySet().stream().filter(e->e.getValue().equals(value)).map(Map.Entry::getKey).findFirst().orElse(null);
            if(phase==null) throw ApiError.bad("INVALID_METRIC","不支持的阶段");
            canonical="dispatched";
        } else if(metric==null||!METRICS.contains(metric)) throw ApiError.bad("INVALID_METRIC","不支持的统计指标");
        var result=new LinkedHashMap<>(repository.details(repository.facts(actor,query),canonical,phase,groupId,day,cursor,limit));
        result.put("metric",metric); result.put("groupBy",query.groupBy()); result.put("filters",query.view()); result.put("range",query.range()); return result;
    }
    @Transactional(readOnly=true,isolation=Isolation.REPEATABLE_READ)
    public String export(Actor actor,AnalyticsQuery query,String resource) {
        if(!Set.of("logs","tasks").contains(resource)) throw ApiError.bad("INVALID_RESOURCE","resource: logs/tasks");
        repository.authorize(actor,query,null); var rows=repository.export(repository.facts(actor,query),resource);
        if(rows.size()>10000) throw ApiError.bad("EXPORT_TOO_LARGE","导出超过10000条，请缩小范围");
        var csv=new StringBuilder("\ufeffid,type,title_or_date,owner_id,owner_name,version,group_id,group_name,occurred_at\r\n");
        for(var row:rows) {
            var cells=new ArrayList<String>(); for(String field:List.of("id","resource","title","owner_id","owner_name","version","group_id","group_name","occurred_at")) cells.add(csv(row.get(field)));
            csv.append(String.join(",",cells)).append("\r\n");
        }
        return csv.toString();
    }
    /** 所有字段加引号；前导空白后的公式字符也防护，多行文本不绕过检测。 */
    public static String csv(Object value) {
        String text=value==null?"":value.toString(); String probe=text.stripLeading();
        if(!text.isEmpty()&&(text.charAt(0)=='\t'||text.charAt(0)=='\r'||text.charAt(0)=='\n')||!probe.isEmpty()&&"=+-@".indexOf(probe.charAt(0))>=0) text="'"+text;
        return "\""+text.replace("\"","\"\"")+"\"";
    }
    public Map<String,Object> timeline(Actor actor,String date,String period,String ownerId) {
        return Map.of("range",Business.range(date,period),"logs",logs.list(actor,new LogQueryService.Query(0,100,ownerId,date,period),false),"tasks",tasks.list(actor,new TaskQueryService.Query(0,100,"",ownerId,date,period)));
    }
}
