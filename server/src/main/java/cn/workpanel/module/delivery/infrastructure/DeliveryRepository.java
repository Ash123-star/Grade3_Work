package cn.workpanel.module.delivery.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.delivery.domain.DeliveryPolicy.Draft;
import org.springframework.stereotype.Repository;
import java.util.*;

@Repository
public class DeliveryRepository {
    private static final String SELECT = """
            SELECT d.id,d.kind,d.title,d.customer_id AS "customerId",c.name AS "customerName",c.status AS "customerStatus",
                d.owner_id AS "ownerId",u.name AS "ownerName",d.business_date::text AS "businessDate",
                d.activity_status AS "activityStatus",d.delivery_status AS "deliveryStatus",
                d.version,d.ended_at AS "endedAt",d.delivered_at AS "deliveredAt",
                COALESCE((SELECT jsonb_agg(p.employee_id ORDER BY p.employee_id)
                    FROM offline_delivery_participants p
                    WHERE p.company_id=d.company_id AND p.delivery_id=d.id),'[]'::jsonb) AS participants,
                COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.employee_id,'name',employee.name)
                    ORDER BY p.employee_id) FROM offline_delivery_participants p JOIN users employee
                    ON employee.company_id=p.company_id AND employee.id=p.employee_id
                    WHERE p.company_id=d.company_id AND p.delivery_id=d.id),'[]'::jsonb) AS "participantDetails"
            FROM offline_deliveries d
            JOIN customers c ON c.company_id=d.company_id AND c.id=d.customer_id
            JOIN users u ON u.company_id=d.company_id AND u.id=d.owner_id
            """;
    private final Db db;

    public DeliveryRepository(Db db) { this.db = db; }

    public Actor actor(Actor actor, boolean lock) {
        return Actor.from(db.one("SELECT * FROM users WHERE company_id=? AND id=?" + (lock ? " FOR SHARE" : ""),
                actor.company(), actor.id()));
    }

    public void customer(Actor a, String id, boolean forWrite) {
        var customer = db.one("SELECT status FROM customers WHERE company_id=? AND id=?" + (forWrite ? " FOR SHARE" : ""),
                a.company(), id);
        if (forWrite && !"ACTIVE".equals(customer.get("status"))) throw new ApiError(409, "CUSTOMER_ARCHIVED", "客户已归档");
    }

    public void validateEmployees(Actor a, Draft draft) {
        var ids = draft.employees();
        var args = new ArrayList<Object>();
        args.add(a.company());
        args.addAll(ids);
        String marks = String.join(",", Collections.nCopies(ids.size(), "?"));
        if (db.rows("SELECT id FROM users WHERE company_id=? AND status='ACTIVE' AND id IN (" + marks
                + ") ORDER BY id FOR SHARE", args.toArray()).size() != ids.size()) {
            throw ApiError.bad("INVALID_EMPLOYEE", "负责人及参与员工必须是本公司在职员工");
        }
    }

    public Map<String, Object> employees(Actor a, String search, boolean activeOnly, int cursor, int limit) {
        String sql = " FROM users WHERE company_id=? AND status IN ('ACTIVE','DISABLED')"
                + (activeOnly ? " AND status='ACTIVE'" : "") + " AND strpos(lower(name),lower(?))>0";
        return page(db.rows("SELECT id,name,status" + sql + " ORDER BY name,id LIMIT ? OFFSET ?",
                a.company(), search, limit, cursor), db.count("SELECT count(*)" + sql, a.company(), search), cursor);
    }

    public Map<String, Object> list(Actor a, String customer, String employee, boolean pendingOnly, int cursor, int limit) {
        var args = new ArrayList<Object>();
        args.add(a.company());
        String where = " WHERE d.company_id=?";
        if (!customer.isEmpty()) {
            customer(a, customer, false);
            where += " AND d.customer_id=?";
            args.add(customer);
        } else {
            db.one("SELECT id FROM users WHERE company_id=? AND id=? AND status IN ('ACTIVE','DISABLED')", a.company(), employee);
            where += """
                     AND (d.owner_id=? OR EXISTS (SELECT 1 FROM offline_delivery_participants p
                        WHERE p.company_id=d.company_id AND p.delivery_id=d.id AND p.employee_id=?))
                    """;
            args.add(employee);
            args.add(employee);
        }
        if (pendingOnly) where += " AND d.delivery_status='PENDING'";
        long count = db.count("SELECT count(*) FROM offline_deliveries d" + where, args.toArray());
        args.add(limit);
        args.add(cursor);
        return page(db.rows(SELECT + where + " ORDER BY d.business_date DESC,d.id LIMIT ? OFFSET ?", args.toArray()), count, cursor);
    }

    private static Map<String, Object> page(List<Map<String, Object>> items, long count, int cursor) {
        long next = (long) cursor + items.size();
        var result = new LinkedHashMap<String, Object>();
        result.put("items", items);
        result.put("total", count);
        result.put("nextCursor", !items.isEmpty() && next < count ? String.valueOf(next) : null);
        return result;
    }

    public Map<String, Object> get(Actor a, String id, boolean lock) {
        if (lock) db.one("SELECT id FROM offline_deliveries WHERE company_id=? AND id=? FOR UPDATE", a.company(), id);
        return db.one(SELECT + " WHERE d.company_id=? AND d.id=?", a.company(), id);
    }

    public Optional<Map<String, Object>> pending(Actor a, String id) {
        return db.rows("""
                SELECT r.id,r.applicant_id AS "applicantId",r.candidate->>'action' AS action,
                    (u.status='ACTIVE' AND u.role='ADMIN' AND NOT u.must_change_password) AS eligible
                FROM review_requests r JOIN users u ON u.company_id=r.company_id AND u.id=r.applicant_id
                WHERE r.company_id=? AND r.target_id=? AND r.kind='OFFLINE_DELIVERY' AND r.status='PENDING'
                """, a.company(), id).stream().findFirst();
    }

    public void insert(Actor a, String id, String customerId, Draft draft) {
        db.update("INSERT INTO offline_deliveries(id,company_id,customer_id,owner_id,kind,title,business_date) VALUES (?,?,?,?,?,?,?::date)",
                id, a.company(), customerId, draft.ownerId(), draft.kind(), draft.title(), draft.businessDate());
        replaceParticipants(a, id, draft);
    }

    public void edit(Actor a, String id, int version, Draft draft) {
        Db.conflict(db.update("""
                UPDATE offline_deliveries SET owner_id=?,kind=?,title=?,business_date=?::date,version=version+1
                WHERE company_id=? AND id=? AND version=?
                """, draft.ownerId(), draft.kind(), draft.title(), draft.businessDate(), a.company(), id, version));
        replaceParticipants(a, id, draft);
    }

    private void replaceParticipants(Actor a, String id, Draft draft) {
        db.update("DELETE FROM offline_delivery_participants WHERE company_id=? AND delivery_id=?", a.company(), id);
        for (String employee : draft.participants()) {
            db.update("INSERT INTO offline_delivery_participants(company_id,delivery_id,employee_id) VALUES (?,?,?)",
                    a.company(), id, employee);
        }
    }

    public void advance(Actor a, String id, int version, boolean endActivity) {
        String update = endActivity
                ? "activity_status='ENDED',ended_at=clock_timestamp()"
                : "delivery_status='DELIVERED',delivered_at=greatest(clock_timestamp(),ended_at)";
        Db.conflict(db.update("UPDATE offline_deliveries SET " + update + ",version=version+1 WHERE company_id=? AND id=? AND version=?",
                a.company(), id, version));
    }

    public void lockKey(Actor a, String key) {
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))", "offline:" + a.company() + ":" + a.id() + ":" + key);
    }

    public String hash(Object value) { return Db.hash(db.write(value)); }

    public Optional<Map<String, Object>> replay(Actor a, String key, String hash) {
        return db.rows("SELECT request_hash,receipt FROM offline_delivery_commands WHERE company_id=? AND actor_id=? AND key=?",
                a.company(), a.id(), key).stream().findFirst().map(row -> {
                    if (!hash.equals(row.get("request_hash"))) {
                        throw new ApiError(409, "IDEMPOTENCY_CONFLICT", "该操作键已用于不同请求");
                    }
                    return db.read(row.get("receipt"));
                });
    }

    public void receipt(Actor a, String key, String hash, Map<String, Object> result) {
        db.update("INSERT INTO offline_delivery_commands(company_id,actor_id,key,request_hash,receipt) VALUES (?,?,?,?,?::jsonb)",
                a.company(), a.id(), key, hash, db.write(result));
    }

    public void auditCreate(Actor a, String id, Object record) {
        db.audit(a, "OFFLINE_DELIVERY_CREATED", id, Map.of(), record, "");
    }
}
