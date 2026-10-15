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
        String where = "company_id=? AND (applicant_id=? OR id IN (SELECT request_id FROM review_steps WHERE reviewer_id=?))";
        return Map.of("items", db.rows("SELECT id,kind,target_id,applicant_id,status,reason,created_at FROM review_requests WHERE " + where + " ORDER BY created_at DESC,id LIMIT ? OFFSET ?", actor.company(), actor.id(), actor.id(), limit, cursor),
            "total", db.count("SELECT count(*) FROM review_requests WHERE " + where, actor.company(), actor.id(), actor.id()), "nextCursor", String.valueOf((long) cursor + limit));
    }

    public void create(String id,Actor a,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason) {
        db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES (?,?,?,?,?,?,?::jsonb,?::jsonb,?)",id,a.company(),a.id(),kind,target,version,db.write(before),db.write(candidate),reason);
    }
    public Map<String,Object> request(String company,String id,boolean lock) { return db.one("SELECT * FROM review_requests WHERE id=? AND company_id=?"+(lock?" FOR UPDATE":""),id,company); }
    public Actor actor(String company,String id) { return Actor.from(db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,company)); }
    public Map<String,Object> policy(String company) { return json(db.one("SELECT review_policy FROM companies WHERE id=?",company).get("review_policy")); }
    public java.util.List<Map<String,Object>> companyReviewer(Actor a,boolean adminOnly) { return db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND company_reviewer=true AND id<>?"+(adminOnly?" AND role='ADMIN'":"")+" ORDER BY id LIMIT 1",a.company(),a.id()); }
    public java.util.List<Map<String,Object>> localReviewer(Actor a,String role,String value) {
        String column=switch(role) { case "LEADER" -> "team_id"; case "DIRECTOR" -> "department_id"; default -> throw new IllegalArgumentException("review role"); };
        return db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND id<>? AND role=? AND "+column+"=? ORDER BY id LIMIT 1",a.company(),a.id(),role,value);
    }
    public void step(String id,String reviewer,Actor a,int position) { db.update("INSERT INTO review_steps(request_id,reviewer_id,applicant_id,position,company_id) VALUES (?,?,?,?,?)",id,reviewer,a.id(),position,a.company()); }
    public long assigned(String id,String actor) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND reviewer_id=?",id,actor); }
    public java.util.List<Map<String,Object>> steps(String id) { return db.rows("SELECT * FROM review_steps WHERE request_id=? ORDER BY position",id); }
    public java.util.List<Map<String,Object>> pending(String id) { return db.rows("SELECT * FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",id); }
    public long lastPosition(String id) { return db.count("SELECT max(position) FROM review_steps WHERE request_id=?",id); }
    public long decidedCount(String id) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state<>'PENDING'",id); }
    public void decideStep(Object id,boolean approve,String reason) { db.update("UPDATE review_steps SET state=?,reason=?,decided_at=now() WHERE id=?",approve?"APPROVED":"REJECTED",reason,id); }
    public void status(String id,String status) { db.update("UPDATE review_requests SET status=? WHERE id=?",status,id); }
    public void clearSteps(String id) { db.update("DELETE FROM review_steps WHERE request_id=?",id); }
    public Map<String,Object> json(Object value) { return db.read(value); }
    public void audit(Actor a,String type,String id,Object before,Object after,String reason) { db.audit(a,type,id,before,after,reason); }
    public void notify(Actor a,String recipient,String type,String id,String dedup) { db.notify(a,recipient,type,id,dedup); }
}
