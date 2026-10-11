package cn.workpanel.module.auth.infrastructure;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import cn.workpanel.module.auth.domain.AuthPolicy.LoginState;
import org.springframework.stereotype.Repository;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;

/** 认证模块数据库访问；写事务由应用服务管理。 */
@Repository
public class AuthRepository {
    private final Db db;
    public AuthRepository(Db db) { this.db = db; }
    public List<Map<String, Object>> departments() { return db.rows("SELECT id,name FROM departments WHERE company_id='default' ORDER BY id"); }
    public void requireDepartment(String id) { db.one("SELECT id FROM departments WHERE id=? AND company_id='default'", id); }
    public Map<String, Object> user(String id) { return db.one("SELECT * FROM users WHERE id=?", id); }
    public Map<String, Object> lockedUser(String id) { return db.one("SELECT * FROM users WHERE id=? FOR UPDATE", id); }
    public List<Map<String, Object>> account(String account) { return db.rows("SELECT * FROM users WHERE account=? FOR UPDATE", account); }
    public void register(String id, String account, String hash, String phone, String name, String department) {
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,role,status) VALUES (?,'default',?,?,?,?,?,'EMPLOYEE','PENDING')", id, account, hash, phone, name, department);
        db.update("INSERT INTO user_roles VALUES (?,'EMPLOYEE')", id);
    }
    public LoginState lockLogin(String key, Instant now) {
        db.update("INSERT INTO auth_login_state(account_hash,updated_at) VALUES (?,?) ON CONFLICT DO NOTHING", key, Timestamp.from(now));
        var row = db.one("SELECT failures,locked_until FROM auth_login_state WHERE account_hash=? FOR UPDATE", key);
        return new LoginState(((Number) row.get("failures")).intValue(), row.get("locked_until") == null ? null : ((Timestamp) row.get("locked_until")).toInstant());
    }
    public void saveLogin(String key, LoginState state, Instant now) {
        db.update("UPDATE auth_login_state SET failures=?,locked_until=?,updated_at=? WHERE account_hash=?", state.failures(), state.lockedUntil() == null ? null : Timestamp.from(state.lockedUntil()), Timestamp.from(now), key);
    }
    public int cleanLoginStates(Instant cutoff, Instant now) {
        return db.update("DELETE FROM auth_login_state WHERE updated_at<? AND (locked_until IS NULL OR locked_until<=?)", Timestamp.from(cutoff), Timestamp.from(now));
    }
    public void session(String token, String user, Instant expires) { db.update("INSERT INTO sessions VALUES (?,?,?)", Db.hash(token), user, Timestamp.from(expires)); }
    public void revoke(String token, String user) { db.update("DELETE FROM sessions WHERE token_hash=? AND user_id=?", Db.hash(token), user); }
    public void password(Actor actor, String hash) {
        db.update("UPDATE users SET password_hash=?,must_change_password=false WHERE id=?", hash, actor.id());
        db.update("DELETE FROM sessions WHERE user_id=?", actor.id());
        db.audit(actor, "PASSWORD_CHANGED", actor.id(), Map.of(), Map.of(), "用户改密并撤销所有会话");
    }
    public boolean hasAdministrator() {
        db.one("SELECT id FROM companies WHERE id='default' FOR UPDATE");
        return db.count("SELECT count(*) FROM users WHERE role='ADMIN'") > 0;
    }
    public boolean occupied(String account, String phone) { return db.count("SELECT count(*) FROM users WHERE account=? OR phone=?", account, phone) > 0; }
    public void administrator(String id, String account, String hash, String phone) {
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status,must_change_password,company_reviewer) VALUES (?,'default',?,?,?,'管理员','ADMIN','ACTIVE',true,true)", id, account, hash, phone);
        db.update("INSERT INTO user_roles VALUES (?,'ADMIN')", id);
        db.audit(Actor.from(user(id)), "INITIALIZED", id, Map.of(), Map.of("role", "ADMIN"), "首次管理员初始化");
    }
}
