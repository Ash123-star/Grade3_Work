package cn.workpanel.module.organization.application;

import cn.workpanel.*;
import cn.workpanel.module.organization.domain.EmployeeProvisioning;
import cn.workpanel.module.organization.infrastructure.AdminConsoleRepository;
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
    public AdminConsoleService(AdminConsoleRepository repository,OrganizationApplicationService organization,ReviewApplicationService reviews,BCryptPasswordEncoder passwords) {
        this.repository=repository;this.organization=organization;this.reviews=reviews;this.passwords=passwords;
    }
    private Actor admin(Actor request) {
        Actor a=repository.current(request);a.requireAdmin();
        if(!a.status().equals("ACTIVE")) throw ApiError.forbidden();
        if(a.mustChange()) throw new ApiError(403,"PASSWORD_CHANGE_REQUIRED","首次登录请修改密码");
        return a;
    }
    public Map<String,Object> employees(Actor request,String search,int cursor,int limit) {
        Actor a=admin(request);Business.page(cursor,limit);
        if(search.length()>100) throw ApiError.bad("INVALID_SEARCH","关键词最多100字");
        return repository.employees(a,search.trim(),cursor,limit);
    }
    public List<Map<String,Object>> departments(Actor request) { return organization.departments(admin(request)); }
    @Transactional public Map<String,Object> create(Actor request,Map<String,Object> body) {
        Actor a=admin(request);var c=EmployeeProvisioning.parse(body);
        try { return repository.create(a,c,passwords.encode(c.password())); }
        catch(DuplicateKeyException e) { throw new ApiError(409,"ACCOUNT_OR_PHONE_EXISTS","账号或手机号已被使用"); }
    }
    @Transactional public Map<String,Object> reviseEmployee(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);Db.fields(body,"version","reason","name","departmentId","status");
        if(body.containsKey("name")&&Db.required(body,"name").length()>100) throw ApiError.bad("INVALID_NAME","姓名最多100字");
        if(body.containsKey("status")&&!Set.of("ACTIVE","DISABLED").contains(Db.str(body,"status"))) throw ApiError.bad("INVALID_STATUS","仅支持启用或停用");
        var command=new LinkedHashMap<>(body);
        var old=repository.employee(a,id);
        // 跨部门调动解除原团队归属，避免旧团队指向其他部门；随同一USER候选审核留痕。
        if(body.containsKey("departmentId")&&!Db.str(old,"department_id").equals(Db.str(body,"departmentId"))) command.put("teamId","");
        return organization.revise(a,id,command);
    }
    public Map<String,Object> priorities(Actor request,int cursor,int limit) { Actor a=admin(request);Business.page(cursor,limit);return repository.priorities(a,cursor,limit); }
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
        return reviews.create(a,"COMPANY_ITEM",id,version,before,c,Db.required(body,"reason"));
    }
    public Map<String,Object> reviews(Actor request,int cursor,int limit) { return reviews.list(admin(request),cursor,limit); }
    public Map<String,Object> review(Actor request,String id) { return reviews.get(admin(request),id); }
    public Map<String,Object> decide(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);return reviews.decide(a,id,ReviewPolicy.decision(body),Db.str(body,"reason"),ReviewPolicy.expectedVersion(body));
    }
}
