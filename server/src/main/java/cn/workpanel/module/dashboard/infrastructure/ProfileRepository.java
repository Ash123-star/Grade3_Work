package cn.workpanel.module.dashboard.infrastructure;

import cn.workpanel.*;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 资料权威列及 JSONB 的持久化边界；更新由应用服务事务包围。 */
@Repository
public class ProfileRepository {
    private final Db db;
    public ProfileRepository(Db db) { this.db=db; }
    public Map<String,Object> user(Actor actor,String id,boolean lock) {
        return db.one("SELECT * FROM users WHERE id=? AND company_id=?"+(lock?" FOR UPDATE":""),id,actor.company());
    }
    public boolean ancestor(Actor actor,String id) { return Business.reportingAncestor(db,actor,id); }
    public Map<String,Object> json(Object value) { return db.read(value); }
    public boolean phoneTaken(String phone,String id) { return db.count("SELECT count(*) FROM users WHERE phone=? AND id<>?",phone,id)>0; }
    public void lockPhone(String phone) { if(phone!=null) db.one("SELECT pg_advisory_xact_lock(hashtextextended(?,0))","profile-phone:"+phone); }
    public void requireOwnAvatar(Actor actor,String id) { db.one("SELECT id FROM attachments WHERE id=? AND owner_id=? AND company_id=?",id,actor.id(),actor.company()); }
    public Map<String,Object> unit(String table,String company,Object id) {
        if(id==null) return Map.of();
        var rows=db.rows("SELECT id,name FROM "+table+" WHERE id=? AND company_id=?",id,company); return rows.isEmpty()?Map.of():rows.getFirst();
    }
    public void update(Actor actor,int version,String phone,String email,String gender,Object age,Map<String,Object> profile) {
        try {
            Db.conflict(db.update("UPDATE users SET phone=?,email=?,gender=?,age=?,profile=?::jsonb,version=version+1 WHERE id=? AND company_id=? AND version=?",phone,email,gender,age,db.write(profile),actor.id(),actor.company(),version));
        } catch(org.springframework.dao.DuplicateKeyException error) {
            // 本语句唯一会改变的唯一键是phone；同时覆盖注册请求竞争同一号码的情况。
            throw new ApiError(409,"PHONE_CONFLICT","手机号已被使用");
        }
        db.audit(actor,"PROFILE_UPDATED",actor.id(),Map.of("version",version),Map.of("version",version+1),"本人资料更新");
    }
}
