package cn.workpanel.module.review.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.springframework.stereotype.Repository;
import java.util.Map;

/** 审核列表数据库范围：仅本公司本人申请或分配给本人的复核。 */
@Repository
public class ReviewRepository {
    private final Db db;
    public ReviewRepository(Db db) { this.db = db; }
    public Map<String, Object> list(Actor actor, int cursor, int limit) {
        String where = "r.company_id=? AND (r.applicant_id=? OR EXISTS (SELECT 1 FROM review_steps s JOIN users reviewer ON reviewer.id=s.reviewer_id AND reviewer.company_id=r.company_id WHERE s.request_id=r.id AND s.reviewer_id=? AND s.state<>'SUPERSEDED' AND "+validReviewer("r","reviewer")+"))";
        var items=db.rows("SELECT r.id,r.kind,r.target_id,r.applicant_id,u.name AS applicant_name,r.status,r.reason,r.expected_version,r.approval_mode,r.decision_source,r.created_at FROM review_requests r JOIN users u ON u.id=r.applicant_id AND u.company_id=r.company_id WHERE " + where + " ORDER BY r.created_at DESC,r.id LIMIT ? OFFSET ?", actor.company(), actor.id(), actor.id(), limit, cursor);
        for(var item:items) {
            var current=currentReviewerView(Db.str(item,"id")); item.put("reviewer_id",current.get("reviewer_id")); item.put("reviewer_name",current.get("reviewer_name")); item.put("reviewer_configured",!current.isEmpty());
        }
        return Map.of("items",items,"total", db.count("SELECT count(*) FROM review_requests r WHERE " + where, actor.company(), actor.id(), actor.id()), "nextCursor", String.valueOf((long) cursor + items.size()));
    }

    public void create(String id,Actor a,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason) {
        String mode=kind.equals("MEMBERSHIP")?"ADMIN_MEMBERSHIP":"DIRECT_MANAGER";
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,approval_mode) VALUES (?,?,?,?,?,?,?::jsonb,?::jsonb,?,?)",id,a.company(),a.id(),kind,target,version,db.write(before),db.write(candidate),reason,mode);
    }
    public Map<String,Object> request(String company,String id,boolean lock) { return db.one("SELECT r.*,u.name AS applicant_name FROM review_requests r JOIN users u ON u.id=r.applicant_id AND u.company_id=r.company_id WHERE r.id=? AND r.company_id=?"+(lock?" FOR UPDATE OF r":""),id,company); }
    public Actor actor(String company,String id) { return Actor.from(db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,company)); }
    public Map<String,Object> policy(String company) { return json(db.one("SELECT review_policy FROM companies WHERE id=?",company).get("review_policy")); }
    public java.util.List<Map<String,Object>> companyReviewer(Actor a,boolean adminOnly) { return db.rows("SELECT id,name FROM users WHERE company_id=? AND status='ACTIVE' AND company_reviewer=true AND id<>?"+(adminOnly?" AND role='ADMIN'":"")+" ORDER BY id LIMIT 1",a.company(),a.id()); }
    public java.util.List<Map<String,Object>> localReviewer(Actor a,String role,String value) {
        String column=switch(role) { case "LEADER" -> "team_id"; case "DIRECTOR" -> "department_id"; default -> throw new IllegalArgumentException("review role"); };
        return db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND id<>? AND role=? AND "+column+"=? ORDER BY id LIMIT 1",a.company(),a.id(),role,value);
    }
    public void step(String id,String reviewer,Actor a,int position) { db.update("INSERT INTO review_steps(request_id,reviewer_id,applicant_id,position,company_id) VALUES (?,?,?,?,?)",id,reviewer,a.id(),position,a.company()); }
    public String directManager(String company,String applicant) {
        if(db.count("WITH RECURSIVE chain(id,path,cycle) AS (SELECT manager_id,ARRAY[employee_id,manager_id],employee_id=manager_id FROM reporting_relations WHERE company_id=? AND employee_id=? UNION ALL SELECT r.manager_id,c.path||r.manager_id,r.manager_id=ANY(c.path) FROM reporting_relations r JOIN chain c ON r.employee_id=c.id WHERE r.company_id=? AND NOT c.cycle) SELECT count(*) FROM chain WHERE cycle",company,applicant,company)>0) return "";
        var rows=db.rows("SELECT m.id FROM reporting_relations r JOIN users e ON e.id=r.employee_id AND e.company_id=r.company_id AND e.status='ACTIVE' JOIN users m ON m.id=r.manager_id AND m.company_id=r.company_id AND m.status='ACTIVE' AND NOT m.must_change_password WHERE r.company_id=? AND r.employee_id=? AND r.manager_id<>r.employee_id",company,applicant);
        return rows.isEmpty()?"":Db.str(rows.getFirst(),"id");
    }
    public String membershipReviewer(String company,String applicant) {
        var rows=db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND NOT must_change_password AND role='ADMIN' AND company_reviewer=true AND id<>? ORDER BY id LIMIT 1",company,applicant);
        return rows.isEmpty()?"":Db.str(rows.getFirst(),"id");
    }
    public long assigned(String id,String actor) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND reviewer_id=?",id,actor); }
    public java.util.List<Map<String,Object>> steps(String id) { return db.rows("SELECT s.*,u.name AS reviewer_name FROM review_steps s LEFT JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id WHERE s.request_id=? ORDER BY s.position",id); }
    public java.util.List<Map<String,Object>> pending(String id) { return db.rows("SELECT * FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",id); }
    public String currentReviewer(String id) { var rows=db.rows("SELECT s.reviewer_id,u.name AS reviewer_name FROM review_steps s JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id WHERE s.request_id=? AND s.state='PENDING' ORDER BY s.position LIMIT 1",id); return rows.isEmpty()?"":Db.str(rows.getFirst(),"reviewer_id"); }
    private static String validReviewer(String request,String user) {
        String cycle="NOT EXISTS (WITH RECURSIVE chain(id,path,cycle) AS (SELECT manager_id,ARRAY[employee_id,manager_id],employee_id=manager_id FROM reporting_relations WHERE company_id="+request+".company_id AND employee_id="+request+".applicant_id UNION ALL SELECT rr.manager_id,c.path||rr.manager_id,rr.manager_id=ANY(c.path) FROM reporting_relations rr JOIN chain c ON rr.employee_id=c.id WHERE rr.company_id="+request+".company_id AND NOT c.cycle) SELECT 1 FROM chain WHERE cycle)";
        return user+".status='ACTIVE' AND NOT "+user+".must_change_password AND "+user+".id<>"+request+".applicant_id AND (("+request+".kind='MEMBERSHIP' AND "+user+".role='ADMIN' AND "+user+".company_reviewer) OR ("+request+".kind<>'MEMBERSHIP' AND "+cycle+" AND EXISTS (SELECT 1 FROM reporting_relations relation JOIN users applicant ON applicant.id=relation.employee_id AND applicant.company_id=relation.company_id AND applicant.status='ACTIVE' WHERE relation.company_id="+request+".company_id AND relation.employee_id="+request+".applicant_id AND relation.manager_id="+user+".id)))";
    }
    public Map<String,Object> currentReviewerView(String id) { var rows=db.rows("SELECT s.reviewer_id,u.name AS reviewer_name FROM review_steps s JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id JOIN review_requests r ON r.id=s.request_id WHERE s.request_id=? AND r.status='PENDING' AND s.state='PENDING' AND "+validReviewer("r","u")+" ORDER BY s.position LIMIT 1",id); return rows.isEmpty()?Map.of():rows.getFirst(); }
    public boolean canReadAssigned(String id,String actor) { return db.count("SELECT count(*) FROM review_steps s JOIN review_requests r ON r.id=s.request_id JOIN users u ON u.id=s.reviewer_id AND u.company_id=r.company_id WHERE s.request_id=? AND s.reviewer_id=? AND s.state<>'SUPERSEDED' AND "+validReviewer("r","u"),id,actor)>0; }
    public long lastPosition(String id) { Object value=db.rows("SELECT max(position) AS value FROM review_steps WHERE request_id=?",id).getFirst().get("value"); return value==null?0:((Number)value).longValue(); }
    public long decidedCount(String id) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state IN ('APPROVED','REJECTED')",id); }
    public void supersedePending(String id,String reason) { db.update("UPDATE review_steps SET state='SUPERSEDED',reason=?,decided_at=now() WHERE request_id=? AND state='PENDING'",reason,id); }
    public void decideStep(Object id,boolean approve,String reason) { db.update("UPDATE review_steps SET state=?,reason=?,decided_at=now() WHERE id=?",approve?"APPROVED":"REJECTED",reason,id); }
    public void status(String id,String status,String decisionSource) { db.update("UPDATE review_requests SET status=?,decision_source=? WHERE id=?",status,decisionSource,id); }
    public Map<String,Object> json(Object value) { return db.read(value); }
    public void audit(Actor a,String type,String id,Object before,Object after,String reason) { db.audit(a,type,id,before,after,reason); }
    public void notify(Actor a,String recipient,String type,String id,String dedup) { db.notify(a,recipient,type,id,dedup); }
}
