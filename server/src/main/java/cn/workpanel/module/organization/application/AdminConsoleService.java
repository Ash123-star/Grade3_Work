package cn.workpanel.module.organization.application;

import cn.workpanel.*;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import cn.workpanel.module.organization.domain.EmployeeIdentity;
import cn.workpanel.module.organization.domain.EmployeeInput;
import cn.workpanel.module.organization.domain.EmployeeConflict;
import cn.workpanel.module.organization.infrastructure.AdminConsoleRepository;
import cn.workpanel.module.dashboard.application.DashboardReviewedRevisionApplication;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.module.review.domain.ReviewPolicy;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 简易后台用例；不依赖客户端角色声明，创建与审计在同一事务。 */
@Service
public class AdminConsoleService {
    private final AdminConsoleRepository repository;
    private final OrganizationApplicationService organization;
    private final ReviewApplicationService reviews;
    private final BCryptPasswordEncoder passwords;
    private final OrganizationValidation validation;
    private final OrganizationReviewedRevisionApplication organizationApply;
    private final DashboardReviewedRevisionApplication dashboardApply;
    public AdminConsoleService(AdminConsoleRepository repository,OrganizationApplicationService organization,ReviewApplicationService reviews,BCryptPasswordEncoder passwords,OrganizationValidation validation,OrganizationReviewedRevisionApplication organizationApply,DashboardReviewedRevisionApplication dashboardApply) {
        this.repository=repository;this.organization=organization;this.reviews=reviews;this.passwords=passwords;this.validation=validation;this.organizationApply=organizationApply;this.dashboardApply=dashboardApply;
    }
    private Actor admin(Actor request) {
        Actor a=repository.current(request);a.requireAdmin();
        if(!a.status().equals("ACTIVE")) throw ApiError.forbidden();
        if(a.mustChange()) throw new ApiError(403,"PASSWORD_CHANGE_REQUIRED","首次登录请修改密码");
        return a;
    }
    public Map<String,Object> employees(Actor request,String search,String department,int cursor,int limit) {
        Actor a=admin(request);Business.page(cursor,limit);
        if(search.length()>100) throw ApiError.bad("INVALID_SEARCH","关键词最多100字");
        if(!department.isBlank()) repository.department(a,department);
        return repository.employees(a,search.trim(),department,cursor,limit);
    }
    public List<Map<String,Object>> departments(Actor request) { return organization.departments(admin(request)); }
    public List<Map<String,Object>> teams(Actor request) { return repository.teams(admin(request)); }
    public List<Map<String,Object>> managers(Actor request) { return repository.managers(admin(request)); }
    @Transactional public Map<String,Object> create(Actor request,Map<String,Object> body) {
        Actor a=admin(request);var c=EmployeeProvisioning.parse(body);
        var conflicts=repository.conflicts("",c.account(),c.phone(),c.idCardNumber());if(!conflicts.isEmpty())throw new EmployeeConflict(conflicts);
        try { return repository.create(a,c,passwords.encode(c.password())); }
        catch(DuplicateKeyException e) { throw repository.duplicate(e); }
    }
    @Transactional public Map<String,Object> reviseEmployee(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);Db.fields(body,"version","reason","name","departmentId","teamId","managerId","status","gender","idCardNumber","businessPosition");
        String gender=body.containsKey("gender")?EmployeeIdentity.gender(body.get("gender")):null;
        String idCardNumber=body.containsKey("idCardNumber")?EmployeeIdentity.idCard(body.get("idCardNumber")):null;
        String name=body.containsKey("name")?EmployeeInput.name(body.get("name")):null;
        if(body.containsKey("status")&&!Set.of("ACTIVE","DISABLED").contains(Db.str(body,"status"))) throw ApiError.bad("INVALID_STATUS","仅支持启用或停用");
        var old=repository.employee(a,id);
        String businessPosition=body.containsKey("businessPosition")?EmployeeInput.position(body.get("businessPosition")):Db.str(old,"business_position");
        if(gender!=null||idCardNumber!=null) EmployeeInput.genderMatches(gender!=null?gender:Db.str(old,"gender").isBlank()?null:Db.str(old,"gender"),idCardNumber!=null?idCardNumber:old.get("id_card_number")==null?null:Db.str(old,"id_card_number"));
        if(idCardNumber!=null) { var conflicts=repository.conflicts(id,null,null,idCardNumber);if(!conflicts.isEmpty())throw new EmployeeConflict(conflicts); }
        var candidate=new LinkedHashMap<String,Object>();
        candidate.put("name",old.get("name"));candidate.put("departmentId",Db.str(old,"department_id"));candidate.put("teamId",Db.str(old,"team_id"));
        candidate.put("role",old.get("role"));candidate.put("status",old.get("status"));candidate.put("dispatchEnabled",old.get("dispatch_enabled"));
        candidate.put("companyReviewer",old.get("company_reviewer"));candidate.put("managerId",repository.manager(id,a.company()));
        var before=new LinkedHashMap<>(candidate);before.put("businessPosition",old.get("business_position"));
        for(String key:List.of("name","departmentId","teamId","managerId","status")) if(body.containsKey(key)) candidate.put(key,body.get(key));
        if(name!=null)candidate.put("name",name);
        if(body.containsKey("departmentId")&&!Db.str(old,"department_id").equals(Db.str(body,"departmentId"))&&!body.containsKey("teamId")) candidate.put("teamId","");
        if("PENDING".equals(old.get("status"))&&"ACTIVE".equals(candidate.get("status"))) {
            Db.required(candidate,"departmentId");Db.required(candidate,"teamId");Db.required(candidate,"managerId");
        }
        if(!Db.str(candidate,"managerId").isBlank()) repository.eligibleManager(a,Db.str(candidate,"managerId"),Db.str(candidate,"departmentId"),Db.str(candidate,"role"),businessPosition);
        validation.user(a.company(),id,candidate);
        var context=ReviewActors.context(a);
        organizationApply.apply("USER",context,context,id,Db.version(body),candidate,Db.required(body,"reason"));
        if(gender!=null||idCardNumber!=null) {
            try { repository.updateIdentity(a,id,gender,idCardNumber); }
            catch(DuplicateKeyException e) { throw repository.duplicate(e); }
        }
        repository.position(a,id,businessPosition);
        if("PENDING".equals(old.get("status"))) repository.finishPendingAccount(a,id,"ACTIVE".equals(candidate.get("status")));
        var safeAfter=new LinkedHashMap<>(candidate);safeAfter.put("businessPosition",businessPosition);if(gender!=null) safeAfter.put("gender",gender);if(idCardNumber!=null) safeAfter.put("idCardUpdated",true);
        repository.audit(a,"ADMIN_EMPLOYEE_UPDATED",id,before,safeAfter,Db.str(body,"reason"));
        return Map.of("id",id,"status","APPLIED","version",Db.version(body)+1);
    }
    public Map<String,Object> priorities(Actor request,int cursor,int limit) { Actor a=admin(request);Business.page(cursor,limit);return repository.priorities(a,cursor,limit); }
    public Map<String,Object> history(Actor request,int cursor,int limit) { Actor a=admin(request);Business.page(cursor,limit);return repository.history(a,cursor,limit); }
    @Transactional public Map<String,Object> revisePriority(Actor request,Map<String,Object> body) {
        Actor a=admin(request);Db.fields(body,"id","version","reason","title","text","pinned","archived","position");
        String id=Db.str(body,"id");int version=Db.version(body);Object before=Map.of();
        if(id.isBlank()) { if(version!=0) throw ApiError.conflict();id=Db.id(); } else before=repository.priority(a,id);
        var c=new LinkedHashMap<String,Object>();
        c.put("title",Db.required(body,"title"));
        if(Db.str(c,"title").length()>200) throw ApiError.bad("INVALID_TITLE","标题最多200字");
        if(body.containsKey("text")&&!(body.get("text") instanceof String)) throw ApiError.bad("INVALID_TEXT","正文必须为文本");
        String text=Db.str(body,"text");if(text.length()>20000) throw ApiError.bad("INVALID_TEXT","正文最多20000字");c.put("text",text);
        for(String key:List.of("pinned","archived")) {
            if(!(body.get(key) instanceof Boolean)) throw ApiError.bad("INVALID_BOOLEAN",key+"必须是布尔值");c.put(key,body.get(key));
        }
        Object position=body.get("position");
        if(!(position instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<0||n.intValue()>10000) throw ApiError.bad("INVALID_POSITION","排序需为0至10000整数");c.put("position",position);
        var context=ReviewActors.context(a);
        dashboardApply.apply("COMPANY_ITEM",context,context,id,version,c,Db.required(body,"reason"));
        repository.audit(a,"ADMIN_COMPANY_ITEM_UPDATED",id,before,c,Db.str(body,"reason"));
        return Map.of("id",id,"status","APPLIED","version",version==0?1:version+1);
    }
    public Map<String,Object> reviews(Actor request,int cursor,int limit) { return reviews.pendingList(admin(request),cursor,limit); }
    public Map<String,Object> review(Actor request,String id) {
        Actor a=admin(request);var result=new LinkedHashMap<>(reviews.get(a,id));
        if("MEMBERSHIP".equals(result.get("kind"))) {
            var target=repository.membershipTarget(a,Db.str(result,"target_id"));
            result.put("target_name",target.get("name"));result.put("target_version",target.get("version"));
            result.put("stale",!"PENDING".equals(target.get("status"))||!Objects.equals(result.get("expected_version"),target.get("version")));
        }
        return result;
    }
    public Map<String,Object> decide(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);return reviews.decide(a,id,ReviewPolicy.decision(body),Db.str(body,"reason"),ReviewPolicy.expectedVersion(body));
    }
}
