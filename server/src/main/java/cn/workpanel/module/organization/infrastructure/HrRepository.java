package cn.workpanel.module.organization.infrastructure;
import cn.workpanel.*;import org.springframework.stereotype.Repository;import java.util.*;
@Repository public class HrRepository {
 private final Db db;public HrRepository(Db db){this.db=db;}
 public Map<String,Object> employee(Actor a,String id){return db.one("SELECT id,name,status,business_position,department_id FROM users WHERE company_id=? AND id=?",a.company(),id);}
 public Map<String,Object> contract(Actor a,String id,boolean lock){return db.one("SELECT * FROM employee_contracts WHERE company_id=? AND id=?"+(lock?" FOR UPDATE":""),a.company(),id);}
 public List<Map<String,Object>> people(Actor a,int cursor,int limit){return db.rows("SELECT u.id,u.name,u.department_id,dep.name department_name,u.business_position,u.status,u.role='ADMIN' AS is_admin,COALESCE(d.duties,'') duties,COALESCE(d.version,0) duties_version,COALESCE(g.access,'NONE') access,COALESCE(g.version,0) grant_version FROM users u LEFT JOIN departments dep ON dep.id=u.department_id AND dep.company_id=u.company_id LEFT JOIN employee_duties d ON d.company_id=u.company_id AND d.employee_id=u.id LEFT JOIN hr_grants g ON g.company_id=u.company_id AND g.user_id=u.id WHERE u.company_id=? ORDER BY u.name,u.id LIMIT ? OFFSET ?",a.company(),limit,cursor);}
 public List<Map<String,Object>> contracts(Actor a,int cursor,int limit){return db.rows("SELECT c.*,u.name employee_name FROM employee_contracts c JOIN users u ON u.id=c.employee_id AND u.company_id=c.company_id WHERE c.company_id=? ORDER BY c.created_at DESC,c.id LIMIT ? OFFSET ?",a.company(),limit,cursor);}
}
