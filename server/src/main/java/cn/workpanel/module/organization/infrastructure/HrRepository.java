package cn.workpanel.module.organization.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Repository
public class HrRepository {
    private final Db db;

    public HrRepository(Db db) {
        this.db = db;
    }

    public boolean allowed(String company, String user, boolean manage) {
        return db.count("""
            SELECT count(*) FROM users u LEFT JOIN hr_grants g ON g.company_id=u.company_id AND g.user_id=u.id
            WHERE u.company_id=? AND u.id=? AND u.status='ACTIVE' AND NOT u.must_change_password
              AND (u.role='ADMIN' OR g.access='MANAGE' OR (NOT ? AND g.access='READ'))
            """, company, user, manage) > 0;
    }

    public void lockEmployee(String company, String id, boolean exclusive) {
        db.one("SELECT id FROM users WHERE company_id=? AND id=?" + (exclusive ? " FOR UPDATE" : " FOR SHARE"),
            company, id);
    }

    public List<Map<String, Object>> people(Actor actor, int cursor, int limit) {
        return db.rows("""
            SELECT u.id,u.name,u.department_id,dep.name department_name,u.business_position,u.status,
              u.role='ADMIN' AS is_admin,COALESCE(d.duties,'') duties,COALESCE(d.version,0) duties_version,
              COALESCE(g.access,'NONE') access,COALESCE(g.version,0) grant_version
            FROM users u
            LEFT JOIN departments dep ON dep.id=u.department_id AND dep.company_id=u.company_id
            LEFT JOIN employee_duties d ON d.company_id=u.company_id AND d.employee_id=u.id
            LEFT JOIN hr_grants g ON g.company_id=u.company_id AND g.user_id=u.id
            WHERE u.company_id=? ORDER BY u.name,u.id LIMIT ? OFFSET ?
            """, actor.company(), limit, cursor);
    }

    public int saveGrant(String company, String employee, String level, int version) {
        return version == 0
            ? db.update("INSERT INTO hr_grants(company_id,user_id,access) VALUES (?,?,?) ON CONFLICT DO NOTHING",
                company, employee, level)
            : db.update("UPDATE hr_grants SET access=?,version=version+1 WHERE company_id=? AND user_id=? AND version=?",
                level, company, employee, version);
    }

    public int saveDuties(String company, String employee, String duties, int version) {
        return version == 0
            ? db.update("INSERT INTO employee_duties(company_id,employee_id,duties) VALUES (?,?,?) ON CONFLICT DO NOTHING",
                company, employee, duties)
            : db.update("UPDATE employee_duties SET duties=?,version=version+1 WHERE company_id=? AND employee_id=? AND version=?",
                duties, company, employee, version);
    }

    public Map<String, Object> contract(Actor actor, String id, boolean lock) {
        return db.one("SELECT * FROM employee_contracts WHERE company_id=? AND id=?" + (lock ? " FOR UPDATE" : ""),
            actor.company(), id);
    }

    public List<Map<String, Object>> contracts(Actor actor, int cursor, int limit) {
        return db.rows("""
            SELECT c.*,u.name employee_name FROM employee_contracts c
            JOIN users u ON u.id=c.employee_id AND u.company_id=c.company_id
            WHERE c.company_id=? ORDER BY c.created_at DESC,c.id LIMIT ? OFFSET ?
            """, actor.company(), limit, cursor);
    }

    public long contractCount(String company) {
        return db.count("SELECT count(*) FROM employee_contracts WHERE company_id=?", company);
    }

    public void createContract(Actor actor, String id, String employee, String title, LocalDate start,
                               LocalDate end, String attachment) {
        db.update("""
            INSERT INTO employee_contracts(id,company_id,employee_id,title,starts_on,ends_on,attachment_id,created_by)
            VALUES (?,?,?,?,?,?,?,?)
            """, id, actor.company(), employee, title, start, end, attachment, actor.id());
    }

    public int updateContract(Actor actor, String id, String employee, String title, LocalDate start,
                              LocalDate end, int version) {
        return db.update("""
            UPDATE employee_contracts SET employee_id=?,title=?,starts_on=?,ends_on=?,version=version+1
            WHERE company_id=? AND id=? AND version=?
            """, employee, title, start, end, actor.company(), id, version);
    }

    public List<String> recipients(String contract) {
        return db.rows("SELECT user_id FROM contract_recipients WHERE contract_id=? ORDER BY user_id", contract)
            .stream().map(row -> Db.str(row, "user_id")).toList();
    }

    public void replaceRecipients(String contract, Set<String> recipients) {
        db.update("DELETE FROM contract_recipients WHERE contract_id=?", contract);
        for (String user : recipients)
            db.update("INSERT INTO contract_recipients(contract_id,user_id) VALUES (?,?)", contract, user);
    }

    public List<Map<String, Object>> versions(String contract) {
        return db.rows("""
            SELECT version,snapshot,changed_by,changed_at FROM employee_contract_versions
            WHERE contract_id=? ORDER BY version DESC
            """, contract);
    }

    public void saveVersion(Actor actor, String id, int version, Map<String, Object> snapshot) {
        db.update("INSERT INTO employee_contract_versions(contract_id,version,snapshot,changed_by) VALUES (?,?,?::jsonb,?)",
            id, version, db.write(snapshot), actor.id());
    }

    public void lockEligibleAttachment(Actor actor, String attachment) {
        db.one("""
            SELECT id FROM attachments WHERE id=? AND company_id=? AND owner_id=? AND storage_state='READY'
              AND task_id IS NULL AND expires_at IS NULL FOR UPDATE
            """, attachment, actor.company(), actor.id());
    }

    public boolean isContractAttachment(String id) {
        return db.count("SELECT count(*) FROM employee_contracts WHERE attachment_id=?", id) > 0;
    }

    public void requireCompanyAttachment(String company, String id) {
        db.one("SELECT id FROM employee_contracts WHERE company_id=? AND attachment_id=?", company, id);
    }

    public boolean attachmentInUse(String id) {
        return isContractAttachment(id)
            || db.count("SELECT count(*) FROM attachment_bindings WHERE attachment_id=?", id) > 0
            || db.count("SELECT count(*) FROM users WHERE profile->>'avatarAttachmentId'=?", id) > 0
            || db.count("SELECT count(*) FROM generated_files WHERE attachment_id=?", id) > 0;
    }

    public List<Map<String, Object>> reminders(Actor actor) {
        return db.rows("""
            SELECT n.id,n.object_id,c.title,c.ends_on,n.created_at FROM notifications n
            JOIN employee_contracts c ON c.company_id=n.company_id AND c.id=n.object_id
            JOIN contract_recipients r ON r.contract_id=c.id AND r.user_id=n.recipient_id
            WHERE n.company_id=? AND n.recipient_id=? AND n.type='CONTRACT_EXPIRY' ORDER BY n.sequence DESC LIMIT 100
            """, actor.company(), actor.id());
    }

    public List<Map<String, Object>> lockExpiring(LocalDate day, String company) {
        return db.rows("""
            SELECT id,company_id,version FROM employee_contracts
            WHERE ends_on=? AND (?::text IS NULL OR company_id=?) FOR UPDATE SKIP LOCKED
            """, day, company, company);
    }

    public int queueReminder(String company, String user, String contract, String key) {
        return db.update("""
            INSERT INTO outbox_events(id,company_id,recipient_id,type,object_id,body,dedup_key)
            VALUES (?,?,?,'CONTRACT_EXPIRY',?,'{}',?) ON CONFLICT(dedup_key) DO NOTHING
            """, Db.id(), company, user, contract, key);
    }

    public void lockPendingReminders(String company, String user) {
        db.rows("""
            SELECT id FROM outbox_events WHERE company_id=? AND recipient_id=? AND type='CONTRACT_EXPIRY'
              AND delivered_at IS NULL ORDER BY created_at FOR UPDATE
            """, company, user);
    }

    public void discardReminders(String company, String user) {
        db.update("DELETE FROM notifications WHERE company_id=? AND recipient_id=? AND type='CONTRACT_EXPIRY'", company, user);
        db.update("""
            UPDATE outbox_events SET delivered_at=now() WHERE company_id=? AND recipient_id=?
              AND type='CONTRACT_EXPIRY' AND delivered_at IS NULL
            """, company, user);
    }

    public void audit(Actor actor, String type, String id, Map<String, Object> metadata, String reason) {
        db.audit(actor, type, id, Map.of(), metadata, reason);
    }
}
