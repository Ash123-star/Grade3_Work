package cn.workpanel.module.customer.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.customer.domain.*;
import org.springframework.stereotype.Repository;
import java.sql.Timestamp;
import java.time.*;
import java.util.*;

@Repository
public class JdbcCustomerRepository implements CustomerRepository {
    private final Db db;
    public JdbcCustomerRepository(Db db) { this.db=db; }
    private static final String PROFILE="""
        id,kind,name,phone,email,external_id,note,status,version,created_at,updated_at,owner_id,
        (SELECT u.name FROM users u WHERE u.company_id=customers.company_id AND u.id=customers.owner_id) owner_name
        """;
    private static final String CUSTOMER=PROFILE+",contacts";

    @Override public Actor current(Actor actor) { return Actor.from(db.one("SELECT * FROM users WHERE id=? AND company_id=?",actor.id(),actor.company())); }

    @Override public Map<String,Object> list(Actor a,String search,String kind,int cursor,int limit) {
        var where=new StringBuilder("company_id=?");
        var args=new ArrayList<Object>(); args.add(a.company());
        if(kind!=null&&!kind.isBlank()) { where.append(" AND kind=?"); args.add(kind); }
        if(search!=null&&!search.isBlank()) {
            where.append(" AND (name ILIKE ? OR phone ILIKE ? OR email ILIKE ? OR external_id ILIKE ?"
                +" OR EXISTS (SELECT 1 FROM users u WHERE u.company_id=customers.company_id AND u.id=owner_id AND u.name ILIKE ?))");
            String like="%"+search.replace("\\","\\\\").replace("%","\\%").replace("_","\\_")+"%";
            args.addAll(List.of(like,like,like,like,like));
        }
        long total=db.count("SELECT count(*) FROM customers WHERE "+where,args.toArray());
        var pageArgs=new ArrayList<>(args); pageArgs.add(limit+1); pageArgs.add(cursor);
        var rows=db.rows("SELECT "+PROFILE+" FROM customers WHERE "+where+" ORDER BY created_at DESC,id LIMIT ? OFFSET ?",pageArgs.toArray());
        boolean more=rows.size()>limit;
        var items=rows.stream().limit(limit).map(JdbcCustomerRepository::customer).toList();
        var result=new LinkedHashMap<String,Object>();
        result.put("items",items); result.put("total",total); result.put("nextCursor",more?String.valueOf(cursor+limit):null);
        return result;
    }

    @Override public Map<String,Object> get(Actor a,String id) {
        return customer(db.one("SELECT "+CUSTOMER+" FROM customers WHERE company_id=? AND id=?",a.company(),id));
    }

    @Override public Map<String,Object> lock(Actor a,String id) {
        return db.one("SELECT status FROM customers WHERE company_id=? AND id=? FOR UPDATE",a.company(),id);
    }

    @Override public Map<String,Object> byExternal(Actor a,String externalId) {
        return customer(db.one("SELECT "+CUSTOMER+" FROM customers WHERE company_id=? AND external_id=?",a.company(),externalId));
    }

    @Override public void lockProfileWrites(Actor a) {
        db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","customer-profile:"+a.company());
    }

    @Override public boolean hasSimilarActiveProfile(Actor a,CustomerDraft d) {
        return !db.rows("""
            SELECT 1 FROM customers WHERE company_id=? AND status='ACTIVE'
              AND ((kind=? AND lower(name)=lower(?)) OR (?<>'' AND phone=?) OR (?<>'' AND lower(email)=lower(?)))
            LIMIT 1
            """,a.company(),d.kind(),d.name(),d.phone(),d.phone(),d.email(),d.email()).isEmpty();
    }

    @Override public void requireActiveOwner(Actor a,String ownerId) {
        if(db.rows("SELECT 1 FROM users WHERE company_id=? AND id=? AND status='ACTIVE' FOR SHARE",a.company(),ownerId).isEmpty())
            throw ApiError.bad("INVALID_EMPLOYEE","业务负责人不是本公司在职员工");
    }

    @Override public Map<String,Object> create(Actor a,CustomerDraft d,List<CustomerDraft.Contact> contacts) {
        String id="cus_"+Db.id();
        db.update("""
            INSERT INTO customers(id,company_id,kind,name,phone,email,external_id,note,status,version,owner_id,contacts)
            VALUES (?,?,?,?,?,?,?,?,'ACTIVE',1,?,?::jsonb)
            """,id,a.company(),d.kind(),d.name(),d.phone(),d.email(),d.externalId(),d.note(),d.ownerId(),db.write(contacts));
        return get(a,id);
    }

    @Override public Map<String,Object> update(Actor a,String id,CustomerDraft d,List<CustomerDraft.Contact> contacts) {
        Db.conflict(db.update("""
            UPDATE customers SET kind=?,name=?,phone=?,email=?,external_id=?,note=?,status=?,version=version+1,updated_at=now(),
                owner_id=CASE WHEN ? THEN ? ELSE owner_id END,contacts=COALESCE(?::jsonb,contacts)
            WHERE company_id=? AND id=? AND version=?
            """,d.kind(),d.name(),d.phone(),d.email(),d.externalId(),d.note(),d.status(),d.ownerProvided(),d.ownerId(),
            contacts==null?null:db.write(contacts),a.company(),id,d.version()));
        return get(a,id);
    }

    @Override public Map<String,Object> membership(Actor a,String customerId) {
        var rows=db.rows("SELECT * FROM customer_memberships WHERE company_id=? AND customer_id=?",a.company(),customerId);
        return rows.isEmpty()?null:membership(rows.getFirst());
    }

    @Override public Map<String,Object> upsertMembership(Actor a,String customerId,MembershipDraft d) {
        var existing=db.rows("SELECT * FROM customer_memberships WHERE company_id=? AND customer_id=?",a.company(),customerId);
        if(existing.isEmpty()) {
            db.update("INSERT INTO customer_memberships(customer_id,company_id,mall_member_id,level,joined_at,expires_at,status,version) VALUES (?,?,?,?,?,?,?,1)",
                customerId,a.company(),d.mallMemberId(),d.level(),d.joinedAt(),d.expiresAt(),d.status());
        } else {
            Db.conflict(db.update("UPDATE customer_memberships SET mall_member_id=?,level=?,joined_at=?,expires_at=?,status=?,version=version+1,updated_at=now() WHERE company_id=? AND customer_id=? AND version=?",
                d.mallMemberId(),d.level(),d.joinedAt(),d.expiresAt(),d.status(),a.company(),customerId,d.version()));
        }
        return membership(a,customerId);
    }

    @Override public List<Map<String,Object>> benefits(Actor a,String customerId) {
        return db.rows("SELECT * FROM customer_benefits WHERE company_id=? AND customer_id=? ORDER BY valid_to DESC,id",a.company(),customerId)
            .stream().map(JdbcCustomerRepository::benefit).toList();
    }

    @Override public Map<String,Object> createBenefit(Actor a,String customerId,BenefitDraft d) {
        String id="ben_"+Db.id();
        db.update("INSERT INTO customer_benefits(id,company_id,customer_id,kind,name,valid_from,valid_to,max_uses,status,version) VALUES (?,?,?,?,?,?,?,?,?,1)",
            id,a.company(),customerId,d.kind(),d.name(),d.validFrom(),d.validTo(),d.maxUses(),"ACTIVE");
        return benefit(db.one("SELECT * FROM customer_benefits WHERE company_id=? AND id=?",a.company(),id));
    }

    @Override public Map<String,Object> benefit(Actor a,String customerId,String benefitId,boolean lock) {
        return benefit(db.one("SELECT * FROM customer_benefits WHERE company_id=? AND customer_id=? AND id=?"+(lock?" FOR UPDATE":""),a.company(),customerId,benefitId));
    }

    @Override public RedemptionReceipt redemptionByKey(Actor a,String benefitId,String eventKey) {
        var rows=db.rows("SELECT * FROM customer_benefit_redemptions WHERE company_id=? AND benefit_id=? AND event_key=?",a.company(),benefitId,eventKey);
        return rows.isEmpty()?null:receipt(rows.getFirst());
    }

    @Override public List<Map<String,Object>> redemptions(Actor a,String benefitId) {
        return db.rows("SELECT * FROM customer_benefit_redemptions WHERE company_id=? AND benefit_id=? ORDER BY redeemed_at DESC,id",a.company(),benefitId)
            .stream().map(JdbcCustomerRepository::redemption).toList();
    }

    @Override public RedemptionReceipt insertRedemption(Actor a,String customerId,String benefitId,String eventKey,String note,long used,Long remaining) {
        String id="red_"+Db.id();
        return receipt(db.one("""
            INSERT INTO customer_benefit_redemptions
                (id,company_id,benefit_id,customer_id,event_key,note,used_at_redemption,remaining_at_redemption)
            VALUES (?,?,?,?,?,?,?,?) RETURNING *
            """,id,a.company(),benefitId,customerId,eventKey,note,used,remaining));
    }

    @Override public long redemptionCount(Actor a,String benefitId) {
        return db.count("SELECT count(*) FROM customer_benefit_redemptions WHERE company_id=? AND benefit_id=?",a.company(),benefitId);
    }

    @Override public List<Map<String,Object>> progress(Actor a,String customerId) {
        return db.rows("SELECT * FROM customer_progress WHERE company_id=? AND customer_id=? ORDER BY created_at DESC,id",a.company(),customerId)
            .stream().map(JdbcCustomerRepository::progress).toList();
    }

    @Override public Map<String,Object> addProgress(Actor a,String customerId,String stage,String note) {
        String id="prg_"+Db.id();
        db.update("INSERT INTO customer_progress(id,company_id,customer_id,stage,note,actor_id) VALUES (?,?,?,?,?,?)",
            id,a.company(),customerId,stage,note,a.id());
        return progressEntry(a,customerId,id);
    }

    @Override public Map<String,Object> progressEntry(Actor a,String customerId,String progressId) {
        return progress(db.one("SELECT * FROM customer_progress WHERE company_id=? AND customer_id=? AND id=?",
            a.company(),customerId,progressId));
    }

    @Override public void audit(Actor a,String type,String id,Object before,Object after,String reason) {
        db.audit(a,type,id,before,after,reason);
    }

    private static Map<String,Object> customer(Map<String,Object> r) {
        var m=new LinkedHashMap<String,Object>();
        m.put("id",Db.str(r,"id")); m.put("kind",Db.str(r,"kind")); m.put("name",Db.str(r,"name"));
        m.put("phone",Db.str(r,"phone")); m.put("email",Db.str(r,"email"));
        m.put("externalId",r.get("external_id")); m.put("note",Db.str(r,"note"));
        m.put("status",Db.str(r,"status")); m.put("version",((Number)r.get("version")).intValue());
        m.put("ownerId",r.get("owner_id"));m.put("ownerName",r.get("owner_name"));
        if(r.containsKey("contacts")) m.put("contacts",r.get("contacts"));
        m.put("createdAt",instant(r.get("created_at"))); m.put("updatedAt",instant(r.get("updated_at")));
        return m;
    }
    private static Map<String,Object> membership(Map<String,Object> r) {
        var m=new LinkedHashMap<String,Object>();
        m.put("customerId",Db.str(r,"customer_id")); m.put("mallMemberId",Db.str(r,"mall_member_id"));
        m.put("level",Db.str(r,"level")); m.put("joinedAt",date(r.get("joined_at"))); m.put("expiresAt",date(r.get("expires_at")));
        m.put("status",Db.str(r,"status")); m.put("version",((Number)r.get("version")).intValue());
        m.put("updatedAt",instant(r.get("updated_at")));
        return m;
    }
    private static Map<String,Object> benefit(Map<String,Object> r) {
        var m=new LinkedHashMap<String,Object>();
        m.put("id",Db.str(r,"id")); m.put("customerId",Db.str(r,"customer_id")); m.put("kind",Db.str(r,"kind"));
        m.put("name",Db.str(r,"name")); m.put("validFrom",date(r.get("valid_from"))); m.put("validTo",date(r.get("valid_to")));
        m.put("maxUses",r.get("max_uses")==null?null:((Number)r.get("max_uses")).intValue());
        m.put("status",Db.str(r,"status")); m.put("version",((Number)r.get("version")).intValue());
        m.put("createdAt",instant(r.get("created_at"))); m.put("updatedAt",instant(r.get("updated_at")));
        return m;
    }
    private static Map<String,Object> redemption(Map<String,Object> r) {
        var m=new LinkedHashMap<String,Object>();
        m.put("id",Db.str(r,"id")); m.put("benefitId",Db.str(r,"benefit_id")); m.put("customerId",Db.str(r,"customer_id"));
        m.put("eventKey",Db.str(r,"event_key")); m.put("note",Db.str(r,"note")); m.put("redeemedAt",instant(r.get("redeemed_at")));
        return m;
    }
    private static RedemptionReceipt receipt(Map<String,Object> r) {
        return new RedemptionReceipt(redemption(r),((Number)r.get("used_at_redemption")).longValue(),
            r.get("remaining_at_redemption") instanceof Number remaining?remaining.longValue():null);
    }
    private static Map<String,Object> progress(Map<String,Object> r) {
        var m=new LinkedHashMap<String,Object>();
        m.put("id",Db.str(r,"id")); m.put("customerId",Db.str(r,"customer_id")); m.put("stage",Db.str(r,"stage"));
        m.put("note",Db.str(r,"note")); m.put("actorId",Db.str(r,"actor_id")); m.put("createdAt",instant(r.get("created_at")));
        return m;
    }
    private static String date(Object value) { return value==null?null:value.toString(); }
    private static Instant instant(Object value) { return value==null?null:((Timestamp)value).toInstant(); }
}
