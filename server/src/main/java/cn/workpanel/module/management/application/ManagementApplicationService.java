package cn.workpanel.module.management.application;

import cn.workpanel.*;
import cn.workpanel.module.management.infrastructure.ManagementRepository;
import cn.workpanel.module.organization.application.OrganizationApplicationService;
import cn.workpanel.module.dashboard.application.CompanyItemApplicationService;
import cn.workpanel.module.dashboard.domain.CompanyItemPolicy;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import java.util.*;

@Service
public class ManagementApplicationService {
    private final ManagementRepository repository;
    private final OrganizationApplicationService organization;
    private final CompanyItemApplicationService items;
    private final ReviewApplicationService reviews;
    public ManagementApplicationService(ManagementRepository repository,OrganizationApplicationService organization,CompanyItemApplicationService items,ReviewApplicationService reviews){this.repository=repository;this.organization=organization;this.items=items;this.reviews=reviews;}
    private void require(Actor actor){actor.requireAdmin();if(!actor.status().equals("ACTIVE")||actor.mustChange())throw ApiError.forbidden();}
    private void query(Actor actor,String search,int cursor,int limit){require(actor);Business.page(cursor,limit);if(search.length()>100)throw ApiError.bad("INVALID_SEARCH","关键词不能超过100字");}
    public Map<String,Object> accounts(Actor a,String search,String status,String department,int cursor,int limit){query(a,search,cursor,limit);if(!Set.of("","PENDING","ACTIVE","DISABLED").contains(status))throw ApiError.bad("INVALID_STATUS","账号状态无效");return repository.accounts(a.company(),search.trim(),status,department,cursor,limit);}
    public Map<String,Object> account(Actor a,String id){require(a);return repository.account(a.company(),id);}
    public Map<String,Object> options(Actor a){require(a);return repository.options(a.company());}
    public Map<String,Object> items(Actor a,String search,String archived,int cursor,int limit){query(a,search,cursor,limit);if(!Set.of("false","true","all").contains(archived))throw ApiError.bad("INVALID_ARCHIVED","归档筛选无效");return repository.items(a.company(),search.trim(),archived,cursor,limit);}
    public Map<String,Object> item(Actor a,String id){require(a);return repository.item(a.company(),id);}
    @org.springframework.transaction.annotation.Transactional
    public Map<String,Object> reviseAccount(Actor a,String id,Map<String,Object> body){require(a);Db.fields(body,"version","reason","name","departmentId","teamId","managerId","role","status","dispatchEnabled");CompanyItemPolicy.reason(body);var current=repository.account(a.company(),id);if(((Number)current.get("version")).intValue()!=Db.version(body))throw ApiError.conflict();if(current.get("status").equals("PENDING")){if(!((List<?>)current.get("pendingReviews")).isEmpty())throw new ApiError(409,"MEMBERSHIP_REVIEW_PENDING","该账号已有待审申请，请打开修改记录处理");if(!Db.str(body,"role").equals("EMPLOYEE")||!Db.str(body,"status").equals("ACTIVE")||Db.str(body,"departmentId").isBlank())throw ApiError.bad("INVALID_MEMBERSHIP","确认归属需选择部门并保持员工角色");}return organization.revise(a,id,body);}
    public Map<String,Object> reviseItem(Actor a,Map<String,Object> body){require(a);return items.revise(a,body);}
    public Map<String,Object> reviews(Actor a,String category,int cursor,int limit){query(a,"",cursor,limit);if(!Set.of("accounts","items").contains(category))throw ApiError.bad("INVALID_CATEGORY","记录分类无效");return repository.reviews(a,category,cursor,limit);}
    public Map<String,Object> review(Actor a,String id){require(a);var detail=reviews.get(a,id);if(!Set.of("USER","MEMBERSHIP","COMPANY_ITEM").contains(Db.str(detail,"kind")))throw ApiError.notFound();return detail;}
    public Map<String,Object> decide(Actor a,String id,Map<String,Object> body){review(a,id);Db.fields(body,"approve","reason");if(!(body.get("approve") instanceof Boolean))throw ApiError.bad("INVALID_DECISION","决定无效");if(Db.str(body,"reason").length()>2000)throw ApiError.bad("INVALID_REASON","理由过长");return reviews.decide(a,id,(Boolean)body.get("approve"),Db.str(body,"reason"));}
    public Map<String,Object> reroute(Actor a,String id){review(a,id);return reviews.reroute(a,id);}
}
