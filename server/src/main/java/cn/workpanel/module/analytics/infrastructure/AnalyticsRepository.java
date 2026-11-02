package cn.workpanel.module.analytics.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.analytics.application.AnalyticsQuery;
import org.springframework.stereotype.Repository;
import java.time.LocalDate;
import java.util.*;

/** 所有指标源于同一授权 facts：事件按每个任务每种事件首次实际时间计数，日志只取已提交。 */
@Repository
public class AnalyticsRepository {
    private final Db db;
    public AnalyticsRepository(Db db) { this.db=db; }
    public void healthy() { db.count("SELECT count(*) FROM companies"); }

    public void authorize(Actor actor,AnalyticsQuery q,String groupId) {
        if(!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        if(q.departmentId()!=null) unit(actor,"departments","department_id",q.departmentId());
        if(q.teamId()!=null) {
            var team=unit(actor,"teams","team_id",q.teamId());
            if(q.departmentId()!=null&&!q.departmentId().equals(team.get("department_id"))) throw ApiError.bad("INVALID_FILTER","团队不属于所选部门");
        }
        if(q.ownerId()!=null) {
            var owner=filterUser(actor,q.ownerId());
            if(!actor.canSeeUser(owner)&&!Business.reportingAncestor(db,actor,q.ownerId())) throw ApiError.forbidden();
            if(q.departmentId()!=null&&!q.departmentId().equals(owner.get("department_id"))||q.teamId()!=null&&!q.teamId().equals(owner.get("team_id"))) throw ApiError.bad("INVALID_FILTER","成员不属于所选组织");
        }
        if(groupId!=null) {
            if(groupId.isBlank()||groupId.length()>100) throw ApiError.bad("INVALID_GROUP","groupId 无效");
            if(!groupId.equals("unassigned")) {
                if(q.groupBy().equals("person")) {
                    var owner=filterUser(actor,groupId);
                    if(!actor.canSeeUser(owner)&&!Business.reportingAncestor(db,actor,groupId)) throw ApiError.forbidden();
                } else unit(actor,q.groupBy().equals("team")?"teams":"departments",q.groupColumn(),groupId);
            } else if(q.groupBy().equals("person")) throw ApiError.bad("INVALID_GROUP","人员分组没有未分配组");
        }
    }
    private Map<String,Object> unit(Actor actor,String table,String column,String id) {
        var units=db.rows("SELECT * FROM "+table+" WHERE id=? AND company_id=?",id,actor.company());
        if(units.isEmpty()) throw ApiError.bad("INVALID_FILTER","组织筛选不存在");
        var unit=units.getFirst();
        if(!actor.global()) {
            var visible=Business.subordinateOwnerClause(actor,"visible_user"); var args=new ArrayList<Object>(visible.args()); args.add(id);
            if(db.count("SELECT count(*) FROM users u JOIN LATERAL (SELECT u.id AS owner_id,u.company_id) visible_user ON true WHERE "+visible.sql()+" AND u."+column+"=?",args.toArray())==0) throw ApiError.forbidden();
        }
        return unit;
    }
    private Map<String,Object> filterUser(Actor actor,String id) {
        var rows=db.rows("SELECT * FROM users WHERE id=? AND company_id=?",id,actor.company());
        if(rows.isEmpty()) throw ApiError.bad("INVALID_FILTER","成员筛选不存在");
        return rows.getFirst();
    }
    public record Source(String sql,List<Object> args) {}
    private String userFilter(AnalyticsQuery q,List<Object> args) {
        String sql="";
        if(q.departmentId()!=null) { sql+=" AND u.department_id=?"; args.add(q.departmentId()); }
        if(q.teamId()!=null) { sql+=" AND u.team_id=?"; args.add(q.teamId()); }
        if(q.ownerId()!=null) { sql+=" AND u.id=?"; args.add(q.ownerId()); }
        return sql;
    }
    /** 一次数据库语句内产生统一事实，避免 CSV 和钻取采用不同任务或日志范围。 */
    public Source facts(Actor actor,AnalyticsQuery q) {
        var scope=Business.taskScope(actor); var args=new ArrayList<Object>(scope.args());
        String taskFilter=userFilter(q,args);
        var logScope=Business.accessibleLogOwnerClause(actor,"l"); args.addAll(logScope.args());
        String logFilter=userFilter(q,args);
        var range=q.range(); args.add(range.from().toString()); args.add(range.to().toString());
        String group="COALESCE(u."+q.groupColumn()+",'unassigned')";
        String name=switch(q.groupBy()) { case "person" -> "u.name"; case "team" -> "COALESCE(tm.name,'未分配')"; default -> "COALESCE(d.name,'未分配')"; };
        String joins=" JOIN users u ON u.id=t.owner_id AND u.company_id=t.company_id LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id LEFT JOIN teams tm ON tm.id=u.team_id AND tm.company_id=u.company_id";
        String sql="WITH task_base AS (SELECT t.id,t.title,t.owner_id,t.version,t.phase,t.deadline,"+group+" AS group_id,"+name+" AS group_name,u.name AS owner_name,"
            +"e.dispatched_at,e.received_at,e.feedback_at,e.accepted_at,e.current_accepted_at FROM tasks t"+joins
            +" LEFT JOIN LATERAL (SELECT min(created_at) FILTER(WHERE type='DISPATCHED') AS dispatched_at,min(created_at) FILTER(WHERE type='RECEIVED') AS received_at,min(created_at) FILTER(WHERE type='FEEDBACK') AS feedback_at,min(created_at) FILTER(WHERE type='ACCEPTED') AS accepted_at,min(created_at) FILTER(WHERE type='ACCEPTED' AND sequence>COALESCE((SELECT max(r.sequence) FROM task_events r WHERE r.task_id=t.id AND r.type='REVISED'),0)) AS current_accepted_at FROM task_events WHERE task_id=t.id AND company_id=t.company_id) e ON true WHERE "+scope.sql()+taskFilter+"),"
            +"log_base AS (SELECT l.id,l.business_date::text AS title,l.owner_id,l.version,l.business_date,"+group+" AS group_id,"+name+" AS group_name,u.name AS owner_name FROM daily_logs l JOIN users u ON u.id=l.owner_id AND u.company_id=l.company_id LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id LEFT JOIN teams tm ON tm.id=u.team_id AND tm.company_id=u.company_id WHERE "+logScope.sql()+" AND l.submitted"+logFilter+"),"
            +"all_facts AS (SELECT t.id,'tasks'::text AS resource,t.title,t.owner_id,t.owner_name,t.version,t.phase,t.deadline,t.group_id,t.group_name,v.metric,v.occurred_at FROM task_base t CROSS JOIN LATERAL (VALUES ('dispatched',t.dispatched_at),('received',t.received_at),('feedback',t.feedback_at),('accepted',t.accepted_at),('onTimeAcceptance',CASE WHEN t.current_accepted_at<=t.deadline THEN t.accepted_at END),('overdue',CASE WHEN t.phase<>'WITHDRAWN' AND t.deadline<now() AND (t.current_accepted_at IS NULL OR t.current_accepted_at>t.deadline) THEN t.deadline END)) v(metric,occurred_at) UNION ALL SELECT l.id,'logs',l.title,l.owner_id,l.owner_name,l.version,NULL::text,NULL::timestamptz,l.group_id,l.group_name,'diarySubmitted',l.business_date::timestamp AT TIME ZONE 'Asia/Shanghai' FROM log_base l),"
            +"facts AS (SELECT *, (occurred_at AT TIME ZONE 'Asia/Shanghai')::date AS bucket FROM all_facts WHERE occurred_at>=?::timestamptz AND occurred_at<?::timestamptz) ";
        return new Source(sql,args);
    }
    public List<Map<String,Object>> counts(Source source) {
        return db.rows(source.sql()+"SELECT group_id,group_name,bucket,metric,count(*) AS value FROM facts GROUP BY group_id,group_name,bucket,metric ORDER BY group_id,bucket,metric",source.args().toArray());
    }
    public List<Map<String,Object>> phases(Source source) {
        return db.rows(source.sql()+"SELECT phase,count(*) AS count FROM facts WHERE metric='dispatched' GROUP BY phase ORDER BY phase",source.args().toArray());
    }
    /** 缺少可靠在职区间的已提交事实不能拿当前人员分母硬算比例。 */
    public List<Map<String,Object>> uncertainDiary(Source source) {
        return db.rows(source.sql()+"SELECT DISTINCT f.group_id,f.bucket FROM facts f JOIN users u ON u.id=f.owner_id WHERE f.metric='diarySubmitted' AND (u.status<>'ACTIVE' OR u.employment_start_date IS NULL OR f.bucket<u.employment_start_date OR f.bucket>(now() AT TIME ZONE 'Asia/Shanghai')::date)",source.args().toArray());
    }
    public Map<String,Object> details(Source source,String metric,String phase,String groupId,LocalDate bucket,int cursor,int limit) {
        var args=new ArrayList<Object>(source.args());
        String where="metric=?"; args.add(metric);
        if(phase!=null) { where+=" AND phase=?"; args.add(phase); }
        if(groupId!=null) { where+=" AND group_id=?"; args.add(groupId); }
        if(bucket!=null) { where+=" AND bucket=?::date"; args.add(bucket.toString()); }
        long total=db.count(source.sql()+"SELECT count(*) FROM facts WHERE "+where,args.toArray());
        args.add(limit); args.add(cursor);
        var rows=db.rows(source.sql()+"SELECT id,resource,title,owner_id,owner_name,version,phase,deadline,group_id,group_name,occurred_at,bucket FROM facts WHERE "+where+" ORDER BY occurred_at DESC,id LIMIT ? OFFSET ?",args.toArray());
        return Map.of("items",rows,"total",total,"nextCursor",cursor+rows.size()<total?Integer.toString(cursor+rows.size()):"");
    }
    /** 日志按业务日期、任务按实际派发日期导出；没有派发事件的历史任务不伪造派发日。 */
    public List<Map<String,Object>> export(Source source,String resource) {
        return db.rows(source.sql()+"SELECT id,resource,title,owner_id,owner_name,version,phase,deadline,group_id,group_name,occurred_at,bucket FROM facts WHERE metric=? ORDER BY occurred_at DESC,id LIMIT 10001",append(source.args(),resource.equals("logs")?"diarySubmitted":"dispatched"));
    }
    private Object[] append(List<Object> original,Object value) { var args=new ArrayList<Object>(original); args.add(value); return args.toArray(); }
    public List<Map<String,Object>> people(Actor actor,AnalyticsQuery q) {
        var visible=Business.subordinateOwnerClause(actor,"visible_user"); var args=new ArrayList<Object>(visible.args());
        String filter=userFilter(q,args);
        return db.rows("SELECT u.id,u.employment_start_date,COALESCE(u."+q.groupColumn()+",'unassigned') AS group_id FROM users u JOIN LATERAL (SELECT u.id AS owner_id,u.company_id) visible_user ON true WHERE "+visible.sql()+" AND u.status='ACTIVE'"+filter+" ORDER BY u.id",args.toArray());
    }
}
