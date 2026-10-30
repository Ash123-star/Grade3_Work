package cn.workpanel.module.review.application;

import cn.workpanel.*;
import cn.workpanel.module.review.domain.ReviewPolicy;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 审核应用服务：MEMBERSHIP 保留管理员确认，其余关键变更使用直属单级审核。 */
@org.springframework.stereotype.Service
public class ReviewApplicationService {
    final ReviewRepository repository;
    static final Set<String> SUPPORTED_KINDS=Set.of("POLICY","MEMBERSHIP","REVIEWER","USER","DEPARTMENT","TEAM","COMPANY_ITEM","LOG","TASK","TASK_REASSIGN","TASK_RESCHEDULE","MEMORY","PROCEDURE","TASK_CREATE","TASK_DELETE");
    final Map<String,ReviewedRevisionApplication> applications;

    public ReviewApplicationService(ReviewRepository repository,List<ReviewedRevisionApplication> handlers) {
        this.repository=repository;
        Map<String,ReviewedRevisionApplication> registry=new HashMap<>();
        for(var handler:handlers) for(String kind:handler.kinds()) if(registry.putIfAbsent(kind,handler)!=null) throw new IllegalStateException("Duplicate reviewed revision handler: "+kind);
        if(!registry.keySet().equals(SUPPORTED_KINDS)) throw new IllegalStateException("Missing reviewed revision handler");
        this.applications=Map.copyOf(registry);
    }

    public Map<String,Object> list(Actor actor,int cursor,int limit) {
        actor=fresh(actor); Business.page(cursor,limit); return repository.list(actor,cursor,limit);
    }

    @Transactional
    public Map<String,Object> create(Actor actor,String kind,String target,int version,Object before,Map<String,Object> candidate,String reason) {
        actor=fresh(actor);
        if(!SUPPORTED_KINDS.contains(kind)) throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        if(kind.equals("LOG")) throw new ApiError(409,"DIRECT_CONTENT_REQUIRED","日报正文请使用24小时内直接更新接口");
        if(!kind.equals("MEMBERSHIP")&&!actor.status().equals("ACTIVE")) throw ApiError.forbidden();
        if(reason==null||reason.isBlank()) throw ApiError.bad("REASON_REQUIRED","关键变更需填写理由");
        String id=Db.id(); repository.create(id,actor,kind,target,version,before,candidate,reason);
        repository.audit(actor,"REVIEW_REQUESTED",id,before,candidate,reason);
        var row=repository.request(actor.company(),id,false);
        if(actor.role().equals("FOUNDER")&&!kind.equals("MEMBERSHIP")) {
            apply(actor,row);
            repository.status(id,"APPROVED","FOUNDER_EXEMPT");
            repository.audit(actor,"REVIEW_APPROVED",id,Map.of("status","PENDING"),Map.of("status","APPROVED","decisionSource","FOUNDER_EXEMPT"),"创始人权限内免审");
            repository.notify(actor,actor.id(),"REVIEW_APPROVED",id,"review-result:"+id+":FOUNDER_EXEMPT");
        } else route(actor,id,kind);
        return get(actor,id);
    }

    /** 只创建一个当前有效直属审核人；MEMBERSHIP 使用管理员例外。 */
    void route(Actor actor,String id,String kind) {
        String reviewer=kind.equals("MEMBERSHIP")
                ? repository.membershipReviewer(actor.company(),actor.id())
                : repository.directManager(actor.company(),actor.id());
        if(reviewer.isBlank()) return;
        int position=(int)repository.lastPosition(id)+1;
        repository.step(id,reviewer,actor,position);
        repository.notify(actor,reviewer,"REVIEW_PENDING",id,"review:"+id+":"+reviewer+":"+position);
    }

    public Map<String,Object> get(Actor actor,String id) {
        actor=fresh(actor);
        var row=repository.request(actor.company(),id,false);
        if(!actor.id().equals(row.get("applicant_id"))&&!repository.canReadAssigned(id,actor.id())) throw ApiError.forbidden();
        return view(row,id);
    }
    private Map<String,Object> view(Map<String,Object> row,String id) {
        var result=new LinkedHashMap<>(row);
        result.put("candidate",repository.json(row.get("candidate")));
        result.put("before_value",repository.json(row.get("before_value")));
        result.put("display_references",repository.displayReferences(Db.str(row,"company_id"),result.get("before_value"),result.get("candidate")));
        result.put("steps",repository.steps(id));
        var current=repository.currentReviewerView(id);
        result.put("reviewer_id",current.getOrDefault("reviewer_id",null));
        result.put("reviewer_name",current.getOrDefault("reviewer_name",null));
        result.put("reviewer_configured",!current.isEmpty());
        return result;
    }

    @Transactional
    public Map<String,Object> decide(Actor actor,String id,boolean approve,String reason,int expectedVersion) {
        var row=repository.request(actor.company(),id,true);
        actor=repository.actor(actor.company(),actor.id());
        if(!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        ReviewPolicy.request(actor.id(),Db.str(row,"applicant_id"),Db.str(row,"status"));
        if(((Number)row.get("expected_version")).intValue()!=expectedVersion) throw ApiError.conflict();
        var steps=repository.pending(id);
        if(steps.isEmpty()||!steps.getFirst().get("reviewer_id").equals(actor.id())) throw ApiError.forbidden();
        String mode=Db.str(row,"approval_mode");
        if(mode.equals("ADMIN_MEMBERSHIP")) {
            if(!Db.str(row,"kind").equals("MEMBERSHIP")||!actor.admin()||!actor.reviewer()) throw ApiError.forbidden();
        } else if(!repository.directManager(Db.str(row,"company_id"),Db.str(row,"applicant_id")).equals(actor.id())) {
            throw ApiError.forbidden();
        }
        ReviewPolicy.reason(approve,reason);
        if(reason==null) reason="";
        repository.decideStep(steps.getFirst().get("id"),approve,reason);
        String source=mode.equals("ADMIN_MEMBERSHIP")?"ADMIN_MEMBERSHIP":"DIRECT_MANAGER";
        Actor applicant=repository.actor(Db.str(row,"company_id"),Db.str(row,"applicant_id"));
        if(!approve) repository.status(id,"REJECTED",source);
        else { apply(actor,row); repository.status(id,"APPROVED",source); }
        repository.audit(actor,approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,Map.of("status","PENDING"),Map.of("status",approve?"APPROVED":"REJECTED","decisionSource",source),reason);
        repository.notify(actor,applicant.id(),approve?"REVIEW_APPROVED":"REVIEW_REJECTED",id,"review-result:"+id+":"+expectedVersion);
        // 此次合法决定可能同时改变组织关系；响应沿用决定时已验证的权限，避免成功应用后读取失败回滚。
        return view(repository.request(actor.company(),id,false),id);
    }

    @Transactional
    public Map<String,Object> reroute(Actor actor,String id) {
        actor=fresh(actor);
        var row=repository.request(actor.company(),id,true);
        if(!actor.id().equals(row.get("applicant_id"))) throw ApiError.forbidden();
        if(Db.str(row,"status").equals("APPROVED")&&Db.str(row,"decision_source").equals("FOUNDER_EXEMPT")) return view(row,id);
        if(!row.get("status").equals("PENDING")) throw ApiError.conflict();
        // 历史已决定步骤只作为审计保留，不阻止仍待审的申请按当前关系重新路由。
        if(Db.str(row,"kind").equals("LOG")) throw new ApiError(409,"DIRECT_CONTENT_REQUIRED","历史日报审核候选已停用");
        repository.supersedePending(id,"申请人按当前审核规则重新路由");
        if(actor.role().equals("FOUNDER")&&!Db.str(row,"kind").equals("MEMBERSHIP")) {
            // 用户明确继续历史申请时才应用；仍经所属模块的当前权限和目标版本校验。
            apply(actor,row); repository.status(id,"APPROVED","FOUNDER_EXEMPT");
            repository.audit(actor,"REVIEW_APPROVED",id,Map.of("status","PENDING"),Map.of("status","APPROVED","decisionSource","FOUNDER_EXEMPT"),"创始人明确继续历史申请");
            repository.notify(actor,actor.id(),"REVIEW_APPROVED",id,"review-result:"+id+":FOUNDER_EXEMPT");
        } else route(actor,id,Db.str(row,"kind"));
        repository.audit(actor,"REVIEW_REROUTED",id,Map.of(),Map.of("approvalMode",Db.str(row,"approval_mode")),"按当前有效关系替换待审步骤，保留历史决定");
        return get(actor,id);
    }

    private Actor fresh(Actor actor) {
        Actor current=repository.actor(actor.company(),actor.id());
        if(current.status().equals("DISABLED")||current.mustChange()) throw ApiError.forbidden();
        return current;
    }

    void apply(Actor approver,Map<String,Object> row) {
        String kind=Db.str(row,"kind"),target=Db.str(row,"target_id");
        int version=((Number)row.get("expected_version")).intValue();
        var candidate=repository.json(row.get("candidate"));
        Actor applicant=repository.actor(Db.str(row,"company_id"),Db.str(row,"applicant_id"));
        if((!applicant.status().equals("ACTIVE")||applicant.mustChange())&&!kind.equals("MEMBERSHIP")) throw ApiError.forbidden();
        var application=applications.get(kind);
        if(application==null) throw ApiError.bad("REVIEW_KIND","不支持的复核类型");
        application.apply(kind,ReviewActors.context(applicant),ReviewActors.context(approver),target,version,candidate,Db.str(row,"reason"));
        repository.audit(approver,"REVISION_APPLIED",target,repository.json(row.get("before_value")),candidate,Db.str(row,"reason"));
    }
}
