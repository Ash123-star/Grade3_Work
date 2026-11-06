package cn.workpanel.module.review.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import cn.workpanel.Business;
import org.springframework.stereotype.Repository;
import java.util.Map;

/** 审核列表数据库范围：仅本公司本人申请或分配给本人的复核。 */
@Repository
public class ReviewRepository {
    private final Db db;
    public ReviewRepository(Db db) { this.db = db; }
    /** Reusable current review visibility; alias r, no notification-based grant. */
    public static Business.Clause readableScope(Actor actor) {
        return new Business.Clause("r.company_id=? AND (r.applicant_id=? OR EXISTS (SELECT 1 FROM review_steps s JOIN users reviewer ON reviewer.id=s.reviewer_id AND reviewer.company_id=r.company_id WHERE s.request_id=r.id AND s.reviewer_id=? AND s.state<>'SUPERSEDED' AND "+validReviewer("r","reviewer")+"))", java.util.List.of(actor.company(),actor.id(),actor.id()));
    }
    public Map<String, Object> list(Actor actor, int cursor, int limit) {
        String where = readableScope(actor).sql();
        var items=db.rows("SELECT r.id,r.kind,r.target_id,r.applicant_id,u.name AS applicant_name,r.status,r.reason,r.expected_version,r.approval_mode,r.decision_source,r.created_at FROM review_requests r JOIN users u ON u.id=r.applicant_id AND u.company_id=r.company_id WHERE " + where + " ORDER BY r.created_at DESC,r.id LIMIT ? OFFSET ?", actor.company(), actor.id(), actor.id(), limit, cursor);
        for(var item:items) {
            var current=currentReviewerView(Db.str(item,"id")); item.put("reviewer_id",current.get("reviewer_id")); item.put("reviewer_name",current.get("reviewer_name")); item.put("reviewer_configured",!current.isEmpty());
        }
        return Map.of("items",items,"total", db.count("SELECT count(*) FROM review_requests r WHERE " + where, actor.company(), actor.id(), actor.id()), "nextCursor", String.valueOf((long) cursor + items.size()));
    }

    public void create(String id,Actor a,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason,String mode) {
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
    private static final String ACTIVE_FOUNDER="u.company_id=? AND u.id<>? AND u.role='FOUNDER' AND u.status='ACTIVE' AND NOT u.must_change_password";
    /** 申请人以外的有效创始人；current 标记当前待审步骤审核人。 */
    public java.util.List<Map<String,Object>> founderPeers(String company,String applicant,String current) {
        return db.rows("SELECT u.id,u.name,u.id=? AS current FROM users u WHERE "+ACTIVE_FOUNDER+" ORDER BY u.id",current,company,applicant);
    }
    public boolean founderPeer(String company,String applicant,String reviewer) {
        return db.count("SELECT count(*) FROM users u WHERE "+ACTIVE_FOUNDER+" AND u.id=?",company,applicant,reviewer)>0;
    }
    /** 默认创始人审核人：直属上级是有效创始人时优先，否则按 id 取第一位。 */
    public String defaultFounderPeer(String company,String applicant) {
        var rows=db.rows("SELECT u.id FROM users u LEFT JOIN reporting_relations r ON r.company_id=u.company_id AND r.employee_id=? AND r.manager_id=u.id WHERE "+ACTIVE_FOUNDER+" ORDER BY (r.manager_id IS NULL),u.id LIMIT 1",applicant,company,applicant);
        return rows.isEmpty()?"":Db.str(rows.getFirst(),"id");
    }
    /** 申请缺少审核人时的提醒对象：有效管理员（不含申请人）；管理员不因此获得审批权。 */
    public java.util.List<String> unassignedRecipients(String company,String applicant) {
        return db.rows("SELECT id FROM users WHERE company_id=? AND id<>? AND role='ADMIN' AND status='ACTIVE' AND NOT must_change_password ORDER BY id",company,applicant).stream().map(r->Db.str(r,"id")).toList();
    }
    /** 公司内仍待审的非日志申请，按 id 排序以固定加锁顺序。 */
    public java.util.List<String> pendingIds(String company) {
        return db.rows("SELECT id FROM review_requests WHERE company_id=? AND status='PENDING' AND kind<>'LOG' ORDER BY id",company).stream().map(r->Db.str(r,"id")).toList();
    }
    /** 锁定仍待审的申请；正被其他事务决定或改派的申请跳过，由该事务按最新关系处理。 */
    public Map<String,Object> lockPending(String company,String id) {
        var rows=db.rows("SELECT * FROM review_requests WHERE id=? AND company_id=? AND status='PENDING' FOR UPDATE SKIP LOCKED",id,company);
        return rows.isEmpty()?null:rows.getFirst();
    }
    public void mode(String id,String mode) { db.update("UPDATE review_requests SET approval_mode=? WHERE id=? AND status='PENDING'",mode,id); }
    public long assigned(String id,String actor) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND reviewer_id=?",id,actor); }
    public java.util.List<Map<String,Object>> steps(String id) { return db.rows("SELECT s.*,u.name AS reviewer_name FROM review_steps s LEFT JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id WHERE s.request_id=? ORDER BY s.position",id); }
    public java.util.List<Map<String,Object>> pending(String id) { return db.rows("SELECT * FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",id); }
    public String currentReviewer(String id) { var rows=db.rows("SELECT s.reviewer_id,u.name AS reviewer_name FROM review_steps s JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id WHERE s.request_id=? AND s.state='PENDING' ORDER BY s.position LIMIT 1",id); return rows.isEmpty()?"":Db.str(rows.getFirst(),"reviewer_id"); }
    private static String validReviewer(String request,String user) {
        String cycle="NOT EXISTS (WITH RECURSIVE chain(id,path,cycle) AS (SELECT manager_id,ARRAY[employee_id,manager_id],employee_id=manager_id FROM reporting_relations WHERE company_id="+request+".company_id AND employee_id="+request+".applicant_id UNION ALL SELECT rr.manager_id,c.path||rr.manager_id,rr.manager_id=ANY(c.path) FROM reporting_relations rr JOIN chain c ON rr.employee_id=c.id WHERE rr.company_id="+request+".company_id AND NOT c.cycle) SELECT 1 FROM chain WHERE cycle)";
        return user+".status='ACTIVE' AND NOT "+user+".must_change_password AND "+user+".id<>"+request+".applicant_id AND (("+request+".kind='MEMBERSHIP' AND "+user+".role='ADMIN' AND "+user+".company_reviewer) OR ("+request+".approval_mode='FOUNDER_PEER' AND "+user+".role='FOUNDER') OR ("+request+".kind<>'MEMBERSHIP' AND "+request+".approval_mode<>'FOUNDER_PEER' AND "+cycle+" AND EXISTS (SELECT 1 FROM reporting_relations relation JOIN users applicant ON applicant.id=relation.employee_id AND applicant.company_id=relation.company_id AND applicant.status='ACTIVE' WHERE relation.company_id="+request+".company_id AND relation.employee_id="+request+".applicant_id AND relation.manager_id="+user+".id)))";
    }
    public Map<String,Object> currentReviewerView(String id) { var rows=db.rows("SELECT s.reviewer_id,u.name AS reviewer_name FROM review_steps s JOIN users u ON u.id=s.reviewer_id AND u.company_id=s.company_id JOIN review_requests r ON r.id=s.request_id WHERE s.request_id=? AND r.status='PENDING' AND s.state='PENDING' AND "+validReviewer("r","u")+" ORDER BY s.position LIMIT 1",id); return rows.isEmpty()?Map.of():rows.getFirst(); }
    public boolean canReadAssigned(String id,String actor) { return db.count("SELECT count(*) FROM review_steps s JOIN review_requests r ON r.id=s.request_id JOIN users u ON u.id=s.reviewer_id AND u.company_id=r.company_id WHERE s.request_id=? AND s.reviewer_id=? AND s.state<>'SUPERSEDED' AND "+validReviewer("r","u"),id,actor)>0; }
    public long lastPosition(String id) { Object value=db.rows("SELECT max(position) AS value FROM review_steps WHERE request_id=?",id).getFirst().get("value"); return value==null?0:((Number)value).longValue(); }
    public long decidedCount(String id) { return db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state IN ('APPROVED','REJECTED')",id); }
    public void supersedePending(String id,String reason) { db.update("UPDATE review_steps SET state='SUPERSEDED',reason=?,decided_at=now() WHERE request_id=? AND state='PENDING'",reason,id); }
    /** 仅更新仍待审的步骤/申请；影响行数不为1说明已被并发处理，返回409并回滚。 */
    public void decideStep(Object id,boolean approve,String reason) { Db.conflict(db.update("UPDATE review_steps SET state=?,reason=?,decided_at=now() WHERE id=? AND state='PENDING'",approve?"APPROVED":"REJECTED",reason,id)); }
    public void status(String id,String status,String decisionSource) { Db.conflict(db.update("UPDATE review_requests SET status=?,decision_source=? WHERE id=? AND status='PENDING'",status,decisionSource,id)); }
    public Map<String,Object> json(Object value) { return db.read(value); }
    /** Called only after review access validation; references never affect approval inputs. */
    public Map<String,Object> displayReferences(String company,Object before,Object candidate) {
        return new ReviewDisplayReferences(db).resolve(company,before,candidate);
    }
    public void audit(Actor a,String type,String id,Object before,Object after,String reason) { db.audit(a,type,id,before,after,reason); }
    public void notify(Actor a,String recipient,String type,String id,String dedup) { db.notify(a,recipient,type,id,dedup); }
}
