package cn.workpanel.module.organization.infrastructure;

import cn.workpanel.*;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import cn.workpanel.module.organization.domain.EmployeeIdentity;
import cn.workpanel.module.organization.domain.EmployeeConflict;
import org.postgresql.util.PSQLException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Repository;
import java.util.*;

/** 管理目录只选择必要字段，所有查询带公司范围，不返回认证秘密。 */
@Repository
public class AdminConsoleRepository {
    private final Db db;
    public AdminConsoleRepository(Db db) { this.db=db; }
    public Actor current(Actor actor) { return Actor.from(db.one("SELECT * FROM users WHERE id=? AND company_id=?",actor.id(),actor.company())); }
    public Map<String,Object> employees(Actor actor,String search,String department,int cursor,int limit) {
        String from=" FROM users u LEFT JOIN departments d ON d.id=u.department_id AND d.company_id=u.company_id LEFT JOIN teams t ON t.id=u.team_id AND t.company_id=u.company_id LEFT JOIN reporting_relations rr ON rr.employee_id=u.id AND rr.company_id=u.company_id LEFT JOIN users m ON m.id=rr.manager_id AND m.company_id=u.company_id WHERE u.company_id=? AND (?='' OR u.department_id=?) AND (u.name ILIKE ? OR u.account ILIKE ? OR u.phone ILIKE ?)";
        String like="%"+search+"%";
        var items=db.rows("SELECT u.id,u.account,u.phone,u.name,u.gender,u.age,u.id_card_number,u.business_position,u.department_id,u.team_id,rr.manager_id,m.name AS manager_name,m.role AS manager_role,m.business_position AS manager_business_position,t.name AS team_name,u.role,u.status,u.version,u.must_change_password,d.name AS department"+from+" ORDER BY d.name,u.name,u.id LIMIT ? OFFSET ?",actor.company(),department,department,like,like,like,limit,cursor);
        for(var item:items) { Object card=item.remove("id_card_number");item.put("has_id_card",card!=null);Integer age=EmployeeIdentity.age(card);item.put("age",age); }
        return Map.of("items",items,"total",db.count("SELECT count(*)"+from,actor.company(),department,department,like,like,like),"nextCursor",String.valueOf((long)cursor+items.size()));
    }
    public List<Map<String,Object>> teams(Actor actor) { return db.rows("SELECT id,name,department_id FROM teams WHERE company_id=? ORDER BY name,id",actor.company()); }
    public List<Map<String,Object>> managers(Actor actor) { return db.rows("SELECT id,name,department_id,team_id,role,business_position FROM users WHERE company_id=? AND status='ACTIVE' AND (role IN ('LEADER','DIRECTOR','ADMIN','FOUNDER') OR business_position<>'NONE') ORDER BY name,id",actor.company()); }
    public void department(Actor actor,String id) { db.one("SELECT id FROM departments WHERE id=? AND company_id=?",id,actor.company()); }
    public Map<String,Object> create(Actor actor,EmployeeProvisioning c,String hash) {
        db.one("SELECT id FROM departments WHERE id=? AND company_id=?",c.department(),actor.company());
        db.one("SELECT id FROM teams WHERE id=? AND company_id=? AND department_id=?",c.team(),actor.company(),c.department());
        eligibleManager(actor,c.manager(),c.department(),"EMPLOYEE",c.businessPosition());
        String id=Db.id();
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,gender,id_card_number,business_position,role,status,must_change_password,dispatch_enabled) VALUES (?,?,?,?,?,?,?,?,?,?,?,'EMPLOYEE','ACTIVE',true,false)",id,actor.company(),c.account(),hash,c.phone(),c.name(),c.department(),c.team(),c.gender(),c.idCardNumber(),c.businessPosition());
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)",id,c.manager(),actor.company());
        db.update("INSERT INTO user_roles(user_id,role_id) VALUES (?,'EMPLOYEE')",id);
        var result=Map.<String,Object>of("id",id,"account",c.account(),"name",c.name(),"department_id",c.department(),"team_id",c.team(),"manager_id",c.manager(),"role","EMPLOYEE","status","ACTIVE","must_change_password",true,"version",1);
        db.audit(actor,"EMPLOYEE_PROVISIONED",id,Map.of(),Map.of("role","EMPLOYEE","status","ACTIVE","departmentId",c.department(),"teamId",c.team(),"managerId",c.manager(),"businessPosition",c.businessPosition()),"管理员直接开通员工账号");
        return result;
    }
    public Map<String,Object> priorities(Actor actor,int cursor,int limit) {
        var items=db.rows("SELECT id,title,body,pinned,archived,position,version FROM dashboard_items WHERE company_id=? AND kind='COMPANY' ORDER BY archived,pinned DESC,position,id LIMIT ? OFFSET ?",actor.company(),limit,cursor);
        return Map.of("items",items,"total",db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND kind='COMPANY'",actor.company()),"nextCursor",String.valueOf((long)cursor+items.size()));
    }
    public Map<String,Object> history(Actor actor,int cursor,int limit) {
        String from=" FROM audit_records a LEFT JOIN users au ON au.id=a.actor_id AND au.company_id=a.company_id LEFT JOIN users tu ON tu.id=a.object_id AND tu.company_id=a.company_id LEFT JOIN dashboard_items item ON item.id=a.object_id AND item.company_id=a.company_id WHERE a.company_id=? AND a.type IN ('EMPLOYEE_PROVISIONED','ADMIN_EMPLOYEE_UPDATED','ADMIN_COMPANY_ITEM_UPDATED')";
        var items=db.rows("SELECT a.id,a.type,a.object_id,a.reason,a.before_value,a.after_value,a.created_at,au.name AS actor_name,COALESCE(tu.name,item.title,a.object_id) AS target_name"+from+" ORDER BY a.id DESC LIMIT ? OFFSET ?",actor.company(),limit,cursor);
        return Map.of("items",items,"total",db.count("SELECT count(*)"+from,actor.company()),"nextCursor",String.valueOf((long)cursor+items.size()));
    }
    public Map<String,Object> priority(Actor actor,String id) { return db.one("SELECT * FROM dashboard_items WHERE id=? AND company_id=? AND kind='COMPANY'",id,actor.company()); }
    public Map<String,Object> employee(Actor actor,String id) { return db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,actor.company()); }
    public Map<String,Object> membershipTarget(Actor actor,String id) { return db.one("SELECT version,status,name FROM users WHERE id=? AND company_id=?",id,actor.company()); }
    public String manager(String id,String company) { var rows=db.rows("SELECT manager_id FROM reporting_relations WHERE employee_id=? AND company_id=?",id,company);return rows.isEmpty()?"":Db.str(rows.getFirst(),"manager_id"); }
    public void eligibleManager(Actor actor,String id,String department,String role,String position) {
        boolean companyLevel=role.equals("DIRECTOR")||!position.equals("NONE");
        String rule=companyLevel?"(role='FOUNDER' OR business_position IN ('GENERAL_MANAGER','DEPUTY_GENERAL_MANAGER'))":"department_id=? AND (role IN ('LEADER','DIRECTOR','FOUNDER') OR business_position<>'NONE')";
        var args=new ArrayList<Object>(List.of(id,actor.company()));if(!companyLevel)args.add(department);
        if(db.rows("SELECT id FROM users WHERE id=? AND company_id=? AND status='ACTIVE' AND "+rule,args.toArray()).isEmpty())
            throw ApiError.bad("INVALID_MANAGER",companyLevel?"部门经理或公司级职位的直属上级须为本公司在职创始人、总经理或分管副总":"直属上级须为同部门在职团队长、部门负责人或创始人");
    }
    public Map<String,String> conflicts(String excludedId,String account,String phone,String card) {
        var row=db.one("SELECT EXISTS(SELECT 1 FROM users WHERE id<>? AND account=?) AS account,EXISTS(SELECT 1 FROM users WHERE id<>? AND phone=?) AS phone,EXISTS(SELECT 1 FROM users WHERE id<>? AND id_card_number=?) AS card",excludedId,account,excludedId,phone,excludedId,card);
        var errors=new LinkedHashMap<String,String>();
        for(String field:List.of("account","phone","idCardNumber")) if(Boolean.TRUE.equals(row.get(field.equals("idCardNumber")?"card":field))) errors.put(field,EmployeeConflict.message(field));
        return errors;
    }
    public RuntimeException duplicate(DuplicateKeyException error) {
        for(Throwable cause=error;cause!=null;cause=cause.getCause()) if(cause instanceof PSQLException pg && pg.getServerErrorMessage()!=null) {
            String constraint=pg.getServerErrorMessage().getConstraint();
            String field=switch(constraint==null?"":constraint) { case "users_account_key"->"account";case "users_phone_key"->"phone";case "users_id_card_number_unique"->"idCardNumber";default->""; };
            if(!field.isEmpty()) return new EmployeeConflict(Map.of(field,EmployeeConflict.message(field)));
        }
        return error;
    }
    public void position(Actor actor,String id,String position) { db.update("UPDATE users SET business_position=? WHERE id=? AND company_id=?",position,id,actor.company()); }

    public void updateIdentity(Actor actor,String id,String gender,String idCardNumber) {
        db.update("UPDATE users SET gender=COALESCE(?,gender),id_card_number=COALESCE(?,id_card_number) WHERE id=? AND company_id=?",gender,idCardNumber,id,actor.company());
    }
    public void audit(Actor actor,String type,String id,Object before,Object after,String reason) { db.audit(actor,type,id,before,after,reason); }
    public void finishPendingAccount(Actor actor,String id,boolean activated) {
        if(activated) db.update("UPDATE users SET employment_start_date=COALESCE(employment_start_date,(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Shanghai')::date) WHERE id=? AND company_id=? AND status='ACTIVE'",id,actor.company());
        db.update("DELETE FROM sessions WHERE user_id=?",id);
        db.update("UPDATE review_steps SET state='SUPERSEDED' WHERE request_id IN (SELECT id FROM review_requests WHERE company_id=? AND target_id=? AND kind='MEMBERSHIP' AND status='PENDING') AND state='PENDING'",actor.company(),id);
        db.update("UPDATE review_requests SET status='SUPERSEDED' WHERE company_id=? AND target_id=? AND kind='MEMBERSHIP' AND status='PENDING'",actor.company(),id);
    }
}
