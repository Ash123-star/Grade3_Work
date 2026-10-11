package cn.workpanel.module.organization.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 所有组织查询在数据库执行公司与当前角色范围过滤。 */
@Repository
public class OrganizationRepository {
    private final Db db;
    public OrganizationRepository(Db db) { this.db = db; }
    public Map<String, Object> user(String id, String company) { return db.one("SELECT * FROM users WHERE id=? AND company_id=?", id, company); }
    public List<Map<String, Object>> departments(String company) { return db.rows("SELECT id,name FROM departments WHERE company_id=? ORDER BY id", company); }
    public List<Map<String, Object>> treeDepartments(Actor actor) {
        return actor.global() ? db.rows("SELECT * FROM departments WHERE company_id=? ORDER BY id", actor.company())
            : db.rows("SELECT * FROM departments WHERE company_id=? AND id=? ORDER BY id", actor.company(), actor.department());
    }
    public List<Map<String, Object>> treeTeams(Actor actor) {
        if (actor.global()) return db.rows("SELECT * FROM teams WHERE company_id=? ORDER BY id", actor.company());
        if (actor.role().equals("DIRECTOR")) return db.rows("SELECT * FROM teams WHERE company_id=? AND department_id=? ORDER BY id", actor.company(), actor.department());
        return db.rows("SELECT * FROM teams WHERE company_id=? AND id=? ORDER BY id", actor.company(), actor.team());
    }
    public Map<String, Object> people(Actor actor, String search, boolean dispatch, int cursor, int limit) {
        var args = new ArrayList<Object>(List.of(actor.company())); args.addAll(Arrays.asList(actor.scopeArgs()));
        args.add("%" + search + "%"); args.add("%" + search + "%");
        String where = "u.company_id=? AND (" + actor.userScope("u") + ") AND " + (dispatch ? "u.status='ACTIVE'" : "u.status<>'DISABLED'") + " AND (u.name ILIKE ? OR d.name ILIKE ?)";
        long total = db.count("SELECT count(*) FROM users u LEFT JOIN departments d ON d.id=u.department_id WHERE " + where, args.toArray());
        args.add(limit); args.add(cursor);
        var items = db.rows("SELECT u.id,u.name,u.role,u.status,u.department_id,u.team_id,u.version,d.name AS department FROM users u LEFT JOIN departments d ON d.id=u.department_id WHERE " + where + " ORDER BY u.name,u.id LIMIT ? OFFSET ?", args.toArray());
        return Map.of("items", items, "total", total, "nextCursor", String.valueOf((long) cursor + items.size()));
    }
    public void department(String id, String company) { db.one("SELECT id FROM departments WHERE id=? AND company_id=?", id, company); }
    public void team(String id, String company, Object department) { db.one("SELECT id FROM teams WHERE id=? AND company_id=? AND department_id=?", id, company, department); }
    public void lockCompany(String company) { db.one("SELECT id FROM companies WHERE id=? FOR UPDATE", company); }
    public void activeManager(String id, String company) { db.one("SELECT id FROM users WHERE id=? AND company_id=? AND status='ACTIVE'", id, company); }
    public String manager(String employee) {
        var rows = db.rows("SELECT manager_id FROM reporting_relations WHERE employee_id=?", employee);
        return rows.isEmpty() ? "" : Db.str(rows.getFirst(), "manager_id");
    }
    public long otherAdministrators(String company, String id) { return db.count("SELECT count(*) FROM users WHERE company_id=? AND role='ADMIN' AND status='ACTIVE' AND id<>?", company, id); }
    public long pendingMembership(String id) { return db.count("SELECT count(*) FROM review_requests WHERE applicant_id=? AND kind='MEMBERSHIP' AND status='PENDING'", id); }
    public Map<String, Object> policy(String company) { return db.one("SELECT version,review_policy FROM companies WHERE id=?", company); }
    public Map<String, Object> policyValues(String company) { return db.read(policy(company).get("review_policy")); }
    public Map<String, Object> unit(String kind, String id, String company) {
        if (!Set.of("departments", "teams").contains(kind)) throw cn.workpanel.ApiError.notFound();
        return db.one("SELECT * FROM " + kind + " WHERE id=? AND company_id=?", id, company);
    }
    public Map<String, Object> audit(String company, int cursor, int limit) {
        return Map.of("items", db.rows("SELECT * FROM audit_records WHERE company_id=? ORDER BY id DESC LIMIT ? OFFSET ?", company, limit, cursor),
            "total", db.count("SELECT count(*) FROM audit_records WHERE company_id=?", company), "nextCursor", String.valueOf((long) cursor + limit));
    }
}
