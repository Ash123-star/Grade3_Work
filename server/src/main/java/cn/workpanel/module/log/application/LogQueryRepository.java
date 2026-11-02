package cn.workpanel.module.log.application;

import cn.workpanel.*;
import java.time.LocalDate;
import java.util.*;

/** 查询持久化边界：授权与过滤在分页和计数之前进入 SQL。 */
final class LogQueryRepository {
    private final Db db;
    LogQueryRepository(Db db) { this.db=db; }
    Map<String,Object> owner(Actor actor,String id) { return db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,actor.company()); }
    void requireDepartment(Actor actor,String id) {
        db.one("SELECT id FROM departments WHERE id=? AND company_id=?",id,actor.company());
        if(actor.global()) return;
        var clause=Business.subordinateOwnerClause(actor,"visible_log");
        // 以成员范围校验筛选，不要求该部门已经存在日志。
        var args=new ArrayList<Object>(clause.args()); args.add(id);
        if(db.count("SELECT count(*) FROM users u JOIN LATERAL (SELECT u.id AS owner_id,u.company_id) visible_log ON true WHERE "+clause.sql()+" AND u.department_id=?",args.toArray())==0) throw ApiError.forbidden();
    }
    Map<String,Object> author(Actor actor,String id) {
        var rows=db.rows("SELECT u.id,u.name,u.department_id,d.name AS department_name FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id WHERE u.id=? AND u.company_id=?",id,actor.company());
        return rows.isEmpty()?Map.of():rows.getFirst();
    }
    /** 月历状态与打开详情使用同一次已提交事实查询，不读取草稿或私人内容。 */
    Map<String,String> submittedIds(String company,String ownerId,LocalDate start,LocalDate end) {
        var result=new LinkedHashMap<String,String>();
        for(var row:db.rows("SELECT id,business_date FROM daily_logs WHERE company_id=? AND owner_id=? AND submitted AND business_date>=?::date AND business_date<=?::date ORDER BY business_date,id",company,ownerId,start.toString(),end.toString()))
            result.put(Integer.toString(localDate(row.get("business_date")).getDayOfMonth()),Db.str(row,"id"));
        return result;
    }
    record Page(List<Map<String,Object>> items,long total) {}
    Page find(Actor actor,LogQueryService.Query q,boolean subordinate,Business.Range range) {
        var args=new ArrayList<Object>();
        String where;
        if(subordinate) {
            var scope=Business.subordinateOwnerClause(actor,"l");
            where=scope.sql()+" AND l.submitted AND l.owner_id<>?"; args.addAll(scope.args()); args.add(actor.id());
        } else {
            var scope=Business.accessibleLogOwnerClause(actor,"l");
            where=scope.sql()+" AND (l.submitted OR l.owner_id=?)"; args.addAll(scope.args()); args.add(actor.id());
        }
        if(q.ownerId()!=null) { where+=" AND l.owner_id=?"; args.add(q.ownerId()); }
        if(q.departmentId()!=null) { where+=" AND u.department_id=?"; args.add(q.departmentId()); }
        if(range!=null) { where+=" AND l.business_date>=?::date AND l.business_date<?::date"; args.add(range.first().toString()); args.add(range.end().toString()); }
        if(q.search()!=null&&!q.search().isBlank()) {
            where+=" AND (strpos(lower(l.body::text),lower(?))>0 OR strpos(lower(u.name),lower(?))>0 OR strpos(lower(u.account),lower(?))>0)";
            for(int i=0;i<3;i++) args.add(q.search().trim());
        }
        String from=" FROM daily_logs l JOIN users u ON u.id=l.owner_id AND u.company_id=l.company_id LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=l.company_id WHERE ";
        long total=db.count("SELECT count(*)"+from+where,args.toArray());
        args.add(q.limit()); args.add(q.cursor());
        var items=db.rows("SELECT l.*,u.name AS author_name,u.department_id,d.name AS department_name"+from+where+" ORDER BY l.business_date DESC,l.id LIMIT ? OFFSET ?",args.toArray());
        return new Page(items,total);
    }
    private static LocalDate localDate(Object value) {
        if(value instanceof java.sql.Date date) return date.toLocalDate();
        if(value instanceof LocalDate date) return date;
        return LocalDate.parse(value.toString());
    }
}
