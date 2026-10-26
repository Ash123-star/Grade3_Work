package cn.workpanel.module.management.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 管理查询显式限定公司及字段；不复用过滤停用账号的业务选人接口。 */
@Repository
public class ManagementRepository {
    private final Db db;
    public ManagementRepository(Db db) { this.db = db; }
    private static final String ACCOUNT_FIELDS = "u.id,u.account,u.name,u.phone,u.role,u.status,u.department_id,u.team_id,u.version,u.dispatch_enabled,u.company_reviewer,d.name AS department,t.name AS team,(SELECT manager_id FROM reporting_relations WHERE employee_id=u.id) AS manager_id";
    public Map<String,Object> accounts(String company,String search,String status,String department,int cursor,int limit) {
        String where="u.company_id=? AND (u.name ILIKE ? OR u.account ILIKE ?) AND (?='' OR u.status=?) AND (?='' OR u.department_id=?)";
        Object[] args={company,"%"+search+"%","%"+search+"%",status,status,department,department};
        var pageArgs=new ArrayList<Object>(Arrays.asList(args));pageArgs.add(limit);pageArgs.add(cursor);
        var items=db.rows("SELECT "+ACCOUNT_FIELDS+" FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id LEFT JOIN teams t ON t.id=u.team_id AND t.company_id=u.company_id WHERE "+where+" ORDER BY u.name,u.id LIMIT ? OFFSET ?",pageArgs.toArray());
        return page(items,db.count("SELECT count(*) FROM users u WHERE "+where,args),cursor);
    }
    public Map<String,Object> account(String company,String id) {
        var row=db.one("SELECT "+ACCOUNT_FIELDS+" FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id LEFT JOIN teams t ON t.id=u.team_id AND t.company_id=u.company_id WHERE u.company_id=? AND u.id=?",company,id);
        row.put("pendingReviews",db.rows("SELECT id,kind,applicant_id FROM review_requests WHERE company_id=? AND target_id=? AND kind IN ('USER','MEMBERSHIP') AND status='PENDING' ORDER BY created_at",company,id));
        return row;
    }
    public Map<String,Object> options(String company) {
        return Map.of("departments",db.rows("SELECT id,name FROM departments WHERE company_id=? ORDER BY name,id",company),
            "teams",db.rows("SELECT id,name,department_id FROM teams WHERE company_id=? ORDER BY name,id",company),
            "managers",db.rows("SELECT id,name,department_id FROM users WHERE company_id=? AND status='ACTIVE' AND role<>'EMPLOYEE' ORDER BY name,id",company));
    }
    public Map<String,Object> items(String company,String search,String archived,int cursor,int limit) {
        String where="company_id=? AND kind='COMPANY' AND (title ILIKE ? OR body->>'text' ILIKE ?)";
        var args=new ArrayList<Object>(List.of(company,"%"+search+"%","%"+search+"%"));
        if(!archived.equals("all")){where+=" AND archived=?";args.add(archived.equals("true"));}
        long total=db.count("SELECT count(*) FROM dashboard_items WHERE "+where,args.toArray());
        args.add(limit);args.add(cursor);
        var result=new LinkedHashMap<String,Object>(page(db.rows("SELECT id,title,COALESCE(body->>'text','') AS text,pinned,archived,position,version FROM dashboard_items WHERE "+where+" ORDER BY pinned DESC,position,id LIMIT ? OFFSET ?",args.toArray()),total,cursor));
        result.put("pinnedCount",db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND pinned AND NOT archived",company));
        result.put("preview",db.rows("SELECT id,title,COALESCE(body->>'text','') AS text,pinned,position,version FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND NOT archived ORDER BY pinned DESC,position,id LIMIT 10",company));
        return result;
    }
    public Map<String,Object> item(String company,String id) {
        return db.one("SELECT id,title,COALESCE(body->>'text','') AS text,pinned,archived,position,version FROM dashboard_items WHERE company_id=? AND kind='COMPANY' AND id=?",company,id);
    }
    public Map<String,Object> reviews(Actor actor,String kind,int cursor,int limit) {
        String types=kind.equals("accounts")?"('USER','MEMBERSHIP')":"('COMPANY_ITEM')";
        String where="r.company_id=? AND r.kind IN "+types+" AND (r.applicant_id=? OR EXISTS (SELECT 1 FROM review_steps s WHERE s.request_id=r.id AND s.reviewer_id=?))";
        var rows=db.rows("SELECT r.id,r.kind,r.target_id,r.applicant_id,r.status,r.reason,r.created_at,u.name AS applicant_name FROM review_requests r LEFT JOIN users u ON u.id=r.applicant_id AND u.company_id=r.company_id WHERE "+where+" ORDER BY r.created_at DESC,r.id LIMIT ? OFFSET ?",actor.company(),actor.id(),actor.id(),limit,cursor);
        return page(rows,db.count("SELECT count(*) FROM review_requests r WHERE "+where,actor.company(),actor.id(),actor.id()),cursor);
    }
    private Map<String,Object> page(List<Map<String,Object>> rows,long total,int cursor) { return Map.of("items",rows,"total",total,"nextCursor",String.valueOf((long)cursor+rows.size())); }
}
