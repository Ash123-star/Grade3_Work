package cn.workpanel.module.log.application;

import cn.workpanel.*;
import java.util.*;

/** 查询持久化边界：授权与过滤在分页和计数之前进入 SQL。 */
final class LogQueryRepository {
    private final Db db;
    LogQueryRepository(Db db) { this.db=db; }
    Map<String,Object> owner(Actor actor,String id) { return db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,actor.company()); }
    Map<String,Object> author(Actor actor,String id) {
        var rows=db.rows("SELECT u.id,u.name,u.department_id,d.name AS department_name FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id WHERE u.id=? AND u.company_id=?",id,actor.company());
        return rows.isEmpty()?Map.of():rows.getFirst();
    }
    record Page(List<Map<String,Object>> items,long total) {}
    Page find(Actor actor,LogQueryService.Query q,boolean subordinate,Business.Range range) {
        var scope=Business.ownerScope(actor,"l"); var args=new ArrayList<Object>(scope.args());
        String where=scope.sql()+" AND (l.submitted OR l.owner_id=?)"; args.add(actor.id());
        if(subordinate) { where+=" AND l.owner_id<>? AND l.submitted"; args.add(actor.id()); }
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
}
