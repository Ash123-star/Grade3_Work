package cn.workpanel.module.organization.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 管理目录只选择必要字段，所有查询带公司范围，不返回认证秘密。 */
@Repository
public class AdminConsoleRepository {
    private final Db db;
    public AdminConsoleRepository(Db db) { this.db=db; }
    public Actor current(Actor actor) { return Actor.from(db.one("SELECT * FROM users WHERE id=? AND company_id=?",actor.id(),actor.company())); }
    public Map<String,Object> employees(Actor actor,String search,int cursor,int limit) {
        String from=" FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id WHERE u.company_id=? AND (u.name ILIKE ? OR u.account ILIKE ? OR u.phone ILIKE ?)";
        String like="%"+search+"%";
        var items=db.rows("SELECT u.id,u.account,u.phone,u.name,u.department_id,u.role,u.status,u.version,u.must_change_password,d.name AS department"+from+" ORDER BY u.created_at DESC,u.id LIMIT ? OFFSET ?",actor.company(),like,like,like,limit,cursor);
        return Map.of("items",items,"total",db.count("SELECT count(*)"+from,actor.company(),like,like,like),"nextCursor",String.valueOf((long)cursor+items.size()));
    }
    public Map<String,Object> create(Actor actor,EmployeeProvisioning c,String hash) {
        db.one("SELECT id FROM departments WHERE id=? AND company_id=?",c.department(),actor.company());
        String id=Db.id();
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,role,status,must_change_password,dispatch_enabled) VALUES (?,?,?,?,?,?,?,'EMPLOYEE','ACTIVE',true,false)",id,actor.company(),c.account(),hash,c.phone(),c.name(),c.department());
        db.update("INSERT INTO user_roles(user_id,role_id) VALUES (?,'EMPLOYEE')",id);
        var result=Map.<String,Object>of("id",id,"account",c.account(),"name",c.name(),"department_id",c.department(),"role","EMPLOYEE","status","ACTIVE","must_change_password",true,"version",1);
        db.audit(actor,"EMPLOYEE_PROVISIONED",id,Map.of(),Map.of("role","EMPLOYEE","status","ACTIVE","departmentId",c.department()),"管理员直接开通员工账号");
        return result;
    }
    public Map<String,Object> priorities(Actor actor,int cursor,int limit) {
        var items=db.rows("SELECT id,title,body,pinned,archived,position,version FROM dashboard_items WHERE company_id=? AND kind='COMPANY' ORDER BY archived,pinned DESC,position,id LIMIT ? OFFSET ?",actor.company(),limit,cursor);
        return Map.of("items",items,"total",db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY'",actor.company()),"nextCursor",String.valueOf((long)cursor+items.size()));
    }
    public Map<String,Object> priority(Actor actor,String id) { return db.one("SELECT * FROM dashboard_items WHERE id=? AND company_id=? AND kind='COMPANY'",id,actor.company()); }
    public Map<String,Object> employee(Actor actor,String id) { return db.one("SELECT department_id FROM users WHERE id=? AND company_id=?",id,actor.company()); }
}
