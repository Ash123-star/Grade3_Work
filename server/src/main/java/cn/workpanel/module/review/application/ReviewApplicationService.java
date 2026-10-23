package cn.workpanel.module.review.application;

import cn.workpanel.*;
import cn.workpanel.module.review.domain.ReviewPolicy;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;

import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@org.springframework.stereotype.Service
public class ReviewApplicationService {
    final ReviewRepository repository;
    public ReviewApplicationService(ReviewRepository repository,List<ReviewedRevisionApplication> handlers) {
        this.repository=repository;
        Map<String,ReviewedRevisionApplication> registry=new HashMap<>();
        for(var handler:handlers) for(String kind:handler.kinds()) if(registry.putIfAbsent(kind,handler)!=null) throw new IllegalStateException("Duplicate reviewed revision handler: "+kind);
        if(!registry.keySet().equals(SUPPORTED_KINDS)) throw new IllegalStateException("Missing reviewed revision handler");
        this.applications=Map.copyOf(registry);
    }
    public Map<String,Object> list(Actor actor,int cursor,int limit) {
        Business.page(cursor,limit);
        return repository.list(actor,cursor,limit);
    }
    static final Set<String> SUPPORTED_KINDS=Set.of("POLICY","MEMBERSHIP","REVIEWER","USER","DEPARTMENT","TEAM","COMPANY_ITEM","LOG","TASK","TASK_REASSIGN","TASK_RESCHEDULE","MEMORY","PROCEDURE","TASK_CREATE","TASK_DELETE");
    static final Set<String> TASK_KINDS=Set.of("TASK","TASK_REASSIGN","TASK_RESCHEDULE","TASK_CREATE","TASK_DELETE");
    final Map<String,ReviewedRevisionApplication> applications;

    @Transactional
    public Map<String,Object> create(Actor a,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason) {
        if(!SUPPORTED_KINDS.contains(kind)) throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        if(reason.isBlank()) throw ApiError.bad("REASON_REQUIRED","关键变更需填写理由");
        String id=Db.id(); repository.create(id,a,kind,target,version,before,candidate,reason);
        route(a,id,kind); repository.audit(a,"REVIEW_REQUESTED",id,before,candidate,reason);
        return repository.request(a.company(),id,false);
    }
    void route(Actor a,String id,String kind) {
        var reviewers=new LinkedHashSet<String>();
        var policy=repository.policy(a.company());
        if(!Set.of("MEMBERSHIP","REVIEWER").contains(kind)) {
            if(!a.team().isBlank()&&(!TASK_KINDS.contains(kind)||Boolean.TRUE.equals(policy.get("taskTeamReview")))) first(reviewers,a,"LEADER",a.team());
            if(!a.department().isBlank()&&(!TASK_KINDS.contains(kind)||Boolean.TRUE.equals(policy.get("taskDepartmentReview")))) first(reviewers,a,"DIRECTOR",a.department());
        }
        var company=repository.companyReviewer(a,Set.of("MEMBERSHIP","REVIEWER").contains(kind));
        if(!company.isEmpty()) reviewers.add(Db.str(company.getFirst(),"id"));
        else { // 没有最终公司复核人不能让下级审核导致生效。
            reviewers.clear();
        }
        int pos=0; for(String reviewer:reviewers) { repository.step(id,reviewer,a,++pos); repository.notify(a,reviewer,"REVIEW_PENDING",id,"review:"+id+":"+reviewer); }
    }
    void first(Set<String> ids,Actor a,String clause,String value) {
        var rows=repository.localReviewer(a,clause,value); if(!rows.isEmpty()) ids.add(Db.str(rows.getFirst(),"id"));
    }
    public Map<String,Object> get(Actor a,String id) {
        var row=repository.request(a.company(),id,false);
        if(!a.id().equals(row.get("applicant_id"))&&repository.assigned(id,a.id())==0) throw ApiError.forbidden();
        var result=new LinkedHashMap<>(row); result.put("candidate",repository.json(row.get("candidate"))); result.put("before_value",repository.json(row.get("before_value"))); result.put("steps",repository.steps(id)); return result;
    }
    @Transactional
    public Map<String,Object> decide(Actor a,String id,boolean approve,String reason) {
        var row=repository.request(a.company(),id,true);
        // 请求可能排队等待申请锁；进入决定时重新读取身份，禁止沿用已撤销的职责快照。
        a=repository.actor(a.company(),a.id());
        if(!a.status().equals("ACTIVE")||a.mustChange()) throw ApiError.forbidden();
        ReviewPolicy.request(a.id(),Db.str(row,"applicant_id"),Db.str(row,"status"));
        var steps=repository.pending(id);
        if(steps.isEmpty()||!steps.getFirst().get("reviewer_id").equals(a.id())) throw ApiError.forbidden();
        String kind=Db.str(row,"kind");
        // 每一步检查当前职责，调岗/撤销权限后不沿用旧审批资格。
        Actor applicant=repository.actor(Db.str(row,"company_id"),Db.str(row,"applicant_id"));
        int position=((Number)steps.getFirst().get("position")).intValue();
        long last=repository.lastPosition(id);
        if(position==last ? !a.reviewer() : !(a.role().equals("LEADER")&&!a.team().isEmpty()&&a.team().equals(applicant.team())||a.role().equals("DIRECTOR")&&!a.department().isEmpty()&&a.department().equals(applicant.department()))) throw ApiError.forbidden();
        if(Set.of("MEMBERSHIP","REVIEWER").contains(kind)&&!a.admin()) throw ApiError.forbidden();
        ReviewPolicy.reason(approve,reason);
        repository.decideStep(steps.getFirst().get("id"),approve,reason);
        if(!approve) repository.status(id,"REJECTED");
        else if(position==last) { apply(a,row); repository.status(id,"APPROVED"); }
        repository.audit(a,approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,Map.of("status","PENDING"),Map.of("position",position,"decision",approve),reason);
        repository.notify(a,applicant.id(),approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,"review-result:"+id+":"+position);
        return get(a,id);
    }
    @Transactional
    public Map<String,Object> reroute(Actor a,String id) {
        var row=repository.request(a.company(),id,true);
        if(!a.id().equals(row.get("applicant_id"))||!row.get("status").equals("PENDING")) throw ApiError.forbidden();
        if(repository.decidedCount(id)>0) throw ApiError.conflict();
        repository.clearSteps(id); route(a,id,Db.str(row,"kind")); return get(a,id);
    }
    void apply(Actor approver,Map<String,Object> row) {
        String kind=Db.str(row,"kind"),target=Db.str(row,"target_id"); int v=((Number)row.get("expected_version")).intValue(); var c=repository.json(row.get("candidate"));
        Actor applicant=repository.actor(Db.str(row,"company_id"),Db.str(row,"applicant_id"));
        if(!applicant.status().equals("ACTIVE")&&!kind.equals("MEMBERSHIP")) throw ApiError.forbidden();
        var application=applications.get(kind);
        if(application==null) throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        application.apply(kind,ReviewActors.context(applicant),ReviewActors.context(approver),target,v,c,Db.str(row,"reason"));
        repository.audit(approver,"REVISION_APPLIED",target,repository.json(row.get("before_value")),c,Db.str(row,"reason"));
    }
    static Object nullable(Map<String,Object> c,String key) { String s=Db.str(c,key); return s.isBlank()?null:s; }
}
