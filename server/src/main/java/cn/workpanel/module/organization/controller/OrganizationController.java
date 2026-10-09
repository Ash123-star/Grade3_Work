package cn.workpanel.module.organization.controller;

import cn.workpanel.*;
import cn.workpanel.module.review.application.ReviewApplicationService;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/organization")
/** 组织与人员接口。查询遵守当前公司和角色数据范围，关键变更通过审核模块生效。 */
public class OrganizationController {
    final Db db; final ReviewApplicationService reviews;
    public OrganizationController(Db db,ReviewApplicationService reviews) { this.db=db; this.reviews=reviews; }
    /** 获取组织树。需要登录；返回范围内部门、团队和人员，不返回密码及私人备注。 */
    @GetMapping public Map<String,Object> tree(HttpServletRequest r) {
        Actor a=Actor.current(r); var users=people(a,"",false,0,100);
        var departments=db.rows("SELECT * FROM departments WHERE company_id=? ORDER BY id",a.company());
        var teams=db.rows("SELECT * FROM teams WHERE company_id=? ORDER BY id",a.company());
        if(!a.global()) { departments.removeIf(d->!d.get("id").equals(a.department())); teams.removeIf(t->a.role().equals("DIRECTOR")?!t.get("department_id").equals(a.department()):!t.get("id").equals(a.team())); }
        return Map.of("departments",departments,"teams",teams,"users",users);
    }
    /** 获取当前公司可见部门。需要登录；员工也可读取其授权范围内结果。 */
    @GetMapping("/departments") public List<Map<String,Object>> departments(HttpServletRequest r) { return db.rows("SELECT id,name FROM departments WHERE company_id=?",Actor.current(r).company()); }
    /** 提交待确认员工的部门归属申请。仅 PENDING 用户；请求含 departmentId、version、reason。 */
    @PostMapping("/membership-application") @Transactional
    public Map<String,Object> membership(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Db.fields(b,"departmentId","version","reason"); Actor a=Actor.current(r); if(!a.status().equals("PENDING")) throw ApiError.conflict();
        String department=Db.required(b,"departmentId"); db.one("SELECT id FROM departments WHERE id=? AND company_id=?",department,a.company());
        if(db.count("SELECT count(*) FROM review_requests WHERE applicant_id=? AND kind='MEMBERSHIP' AND status='PENDING'",a.id())>0) throw ApiError.conflict();
        return reviews.create(a,"MEMBERSHIP",a.id(),Db.version(b),Map.of("status","PENDING","departmentId",a.department()),Map.of("status","ACTIVE","departmentId",department),Db.required(b,"reason"));
    }
    /** 获取任务审核策略。仅管理员；返回当前生效版本。 */
    @GetMapping("/review-policy") public Map<String,Object> policy(HttpServletRequest r) { Actor a=Actor.current(r); a.requireAdmin(); return db.one("SELECT version,review_policy FROM companies WHERE id=?",a.company()); }
    /** 提交任务审核策略候选版本。仅管理员；需 version、reason，待独立复核通过后生效。 */
    @PostMapping("/review-policy/revisions") @Transactional
    public Map<String,Object> policyRevision(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); a.requireAdmin(); Db.fields(b,"version","reason","taskTeamReview","taskDepartmentReview");
        var current=db.one("SELECT review_policy FROM companies WHERE id=?",a.company()); var candidate=db.read(current.get("review_policy"));
        var before=new LinkedHashMap<>(candidate); for(String k:List.of("taskTeamReview","taskDepartmentReview")) if(b.containsKey(k)) { if(!(b.get(k) instanceof Boolean)) throw ApiError.bad("INVALID_POLICY","复核策略必须为布尔值"); candidate.put(k,b.get(k)); }
        return reviews.create(a,"POLICY",a.company(),Db.version(b),before,candidate,Db.required(b,"reason"));
    }
    /** 分页查询可见人员。dispatch=true 时要求派发资格；支持 search、cursor、limit。 */
    @GetMapping("/people") public Map<String,Object> people(HttpServletRequest r,@RequestParam(defaultValue="") String search,@RequestParam(defaultValue="false") boolean dispatch,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        Actor a=Actor.current(r); Business.page(cursor,limit); if(dispatch) a.requireDispatch(); return people(a,search,dispatch,cursor,limit);
    }
    Map<String,Object> people(Actor a,String search,boolean dispatch,int cursor,int limit) {
        var args=new ArrayList<Object>(List.of(a.company())); args.addAll(Arrays.asList(a.scopeArgs())); args.add("%"+search+"%"); args.add("%"+search+"%");
        String where="u.company_id=? AND ("+a.userScope("u")+") AND "+(dispatch?"u.status='ACTIVE'":"u.status<>'DISABLED'")+" AND (u.name ILIKE ? OR d.name ILIKE ?)";
        long total=db.count("SELECT count(*) FROM users u LEFT JOIN departments d ON d.id=u.department_id WHERE "+where,args.toArray()); args.add(limit); args.add(cursor);
        return Map.of("items",db.rows("SELECT u.id,u.name,u.role,u.status,u.department_id,u.team_id,u.version,d.name AS department FROM users u LEFT JOIN departments d ON d.id=u.department_id WHERE "+where+" ORDER BY u.name,u.id LIMIT ? OFFSET ?",args.toArray()),"total",total,"nextCursor",String.valueOf(cursor+limit));
    }
    /** 申请公司复核职责。仅 ACTIVE 非复核人；需 reason、version，由管理员独立审批。 */
    @PostMapping("/reviewer-application") @Transactional
    public Map<String,Object> reviewer(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        Db.fields(b,"reason","version"); Actor a=Actor.current(r); if(a.reviewer()) throw ApiError.conflict(); var u=db.one("SELECT * FROM users WHERE id=?",a.id());
        return reviews.create(a,"REVIEWER",a.id(),Db.version(b),Map.of("companyReviewer",u.get("company_reviewer")),Map.of("companyReviewer",true),Db.required(b,"reason"));
    }
    /** 提交人员角色、组织或权限候选版本。仅管理员；需 version、reason，禁止直接越过审核。 */
    @PostMapping("/users/{id}/revisions") @Transactional
    public Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); a.requireAdmin(); Db.fields(b,"version","reason","name","departmentId","teamId","role","status","dispatchEnabled","companyReviewer","managerId");
        var old=db.one("SELECT * FROM users WHERE id=? AND company_id=?",id,a.company());
        var c=new LinkedHashMap<String,Object>(); c.put("name",old.get("name")); c.put("departmentId",Db.str(old,"department_id")); c.put("teamId",Db.str(old,"team_id")); c.put("role",old.get("role")); c.put("status",old.get("status")); c.put("dispatchEnabled",old.get("dispatch_enabled")); c.put("companyReviewer",old.get("company_reviewer"));
        var relations=db.rows("SELECT manager_id FROM reporting_relations WHERE employee_id=?",id); c.put("managerId",relations.isEmpty()?"":relations.getFirst().get("manager_id"));
        var before=new LinkedHashMap<>(c); for(String k:c.keySet()) if(b.containsKey(k)) c.put(k,b.get(k)); validateUser(db,a.company(),id,c);
        return reviews.create(a,"USER",id,Db.version(b),before,c,Db.required(b,"reason"));
    }
    /** 提交部门或团队候选版本。仅管理员；kind 只能是 departments 或 teams；需 version、reason。 */
    @PostMapping("/{kind}/revisions") @Transactional
    public Map<String,Object> unit(HttpServletRequest r,@PathVariable String kind,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); a.requireAdmin(); Db.fields(b,"id","name","departmentId","version","reason"); if(!Set.of("departments","teams").contains(kind)) throw ApiError.notFound();
        String id=Db.str(b,"id"); int v=Db.version(b); Object before=Map.of(); if(id.isBlank()) { if(v!=0) throw ApiError.conflict(); id=Db.id(); } else { before=db.one("SELECT * FROM "+kind+" WHERE id=? AND company_id=?",id,a.company()); }
        var c=new LinkedHashMap<String,Object>(); c.put("name",Db.required(b,"name")); if(kind.equals("teams")) { String dept=Db.required(b,"departmentId"); db.one("SELECT id FROM departments WHERE id=? AND company_id=?",dept,a.company()); c.put("departmentId",dept); }
        return reviews.create(a,kind.equals("teams")?"TEAM":"DEPARTMENT",id,v,before,c,Db.required(b,"reason"));
    }
    /** 分页读取公司审计记录。仅管理员；支持 cursor、limit；返回 items、total、nextCursor。 */
    @GetMapping("/audit") public Map<String,Object> audit(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) { Actor a=Actor.current(r); a.requireAdmin(); Business.page(cursor,limit); return Map.of("items",db.rows("SELECT * FROM audit_records WHERE company_id=? ORDER BY id DESC LIMIT ? OFFSET ?",a.company(),limit,cursor),"total",db.count("SELECT count(*) FROM audit_records WHERE company_id=?",a.company()),"nextCursor",String.valueOf(cursor+limit)); }
    public static void validateUser(Db db,String company,String id,Map<String,Object> c) {
        // 先锁公司，再读取汇报链；并发审批不能分别验证后形成环。
        db.one("SELECT id FROM companies WHERE id=? FOR UPDATE",company);
        if(!Set.of("ADMIN","FOUNDER","DIRECTOR","LEADER","EMPLOYEE").contains(Db.required(c,"role"))||!Set.of("ACTIVE","DISABLED").contains(Db.required(c,"status"))) throw ApiError.bad("INVALID_ROLE","角色或状态无效");
        Db.required(c,"name"); if(!(c.get("dispatchEnabled") instanceof Boolean)||!(c.get("companyReviewer") instanceof Boolean)) throw ApiError.bad("INVALID_PERMISSION","权限开关必须为布尔值");
        if(!Db.str(c,"departmentId").isBlank()) db.one("SELECT id FROM departments WHERE id=? AND company_id=?",c.get("departmentId"),company);
        if(!Db.str(c,"teamId").isBlank()) db.one("SELECT id FROM teams WHERE id=? AND company_id=? AND department_id=?",c.get("teamId"),company,c.get("departmentId"));
        if(c.get("role").equals("DIRECTOR")&&Db.str(c,"departmentId").isBlank()||c.get("role").equals("LEADER")&&Db.str(c,"teamId").isBlank()) throw ApiError.bad("MISSING_ORGANIZATION","管理角色需配置对应部门/团队");
        String manager=Db.str(c,"managerId"); var seen=new HashSet<String>(); seen.add(id);
        while(!manager.isBlank()) {
            if(!seen.add(manager)) throw ApiError.bad("REPORTING_CYCLE","禁止循环汇报关系"); db.one("SELECT id FROM users WHERE id=? AND company_id=? AND status='ACTIVE'",manager,company);
            var parent=db.rows("SELECT manager_id FROM reporting_relations WHERE employee_id=?",manager); manager=parent.isEmpty()?"":Db.str(parent.getFirst(),"manager_id");
        }
        if((!c.get("role").equals("ADMIN")||!c.get("status").equals("ACTIVE"))&&db.count("SELECT count(*) FROM users WHERE company_id=? AND role='ADMIN' AND status='ACTIVE' AND id<>?",company,id)==0) throw ApiError.bad("LAST_ADMIN","不能停用或降级最后一个管理员");
    }
}
