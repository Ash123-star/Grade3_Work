package cn.workpanel.module.review.application;

import cn.workpanel.*;
import cn.workpanel.module.review.domain.ReviewPolicy;
import cn.workpanel.module.review.infrastructure.ReviewRepository;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.module.review.api.ReviewedRevisionApplication;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

/** 审核应用服务：MEMBERSHIP 保留管理员确认；创始人在业务权限内免审，不按创始人数互审；其余关键变更使用直属单级审核。 */
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
        String mode=mode(actor,kind);
        String id=Db.id(); repository.create(id,actor,kind,target,version,before,candidate,reason,mode==null?"DIRECT_MANAGER":mode);
        repository.audit(actor,"REVIEW_REQUESTED",id,before,candidate,reason);
        var row=repository.request(actor.company(),id,false);
        if(mode==null) {
            apply(actor,row);
            repository.status(id,"APPROVED","FOUNDER_EXEMPT");
            repository.audit(actor,"REVIEW_APPROVED",id,Map.of("status","PENDING"),Map.of("status","APPROVED","decisionSource","FOUNDER_EXEMPT"),"创始人权限内免审");
            repository.notify(actor,actor.id(),"REVIEW_APPROVED",id,"review-result:"+id+":FOUNDER_EXEMPT");
        } else route(actor,id,mode);
        return get(actor,id);
    }

    /** 申请人当前适用的审核模式；null 表示创始人权限内免审。 */
    String mode(Actor applicant,String kind) {
        if(kind.equals("MEMBERSHIP")) return "ADMIN_MEMBERSHIP";
        if(!applicant.role().equals("FOUNDER")) return "DIRECT_MANAGER";
        return null;
    }

    /** 按模式只创建一个当前有效审核人；找不到时保持待审并提醒申请人和管理员。返回是否已分配。 */
    boolean route(Actor actor,String id,String mode) {
        String reviewer=switch(mode) {
            case "ADMIN_MEMBERSHIP" -> repository.membershipReviewer(actor.company(),actor.id());
            case "FOUNDER_PEER" -> throw new ApiError(409,"REVIEW_RULE_RETIRED","旧创始人互审已停用，请重新提交");
            default -> repository.directManager(actor.company(),actor.id());
        };
        int position=(int)repository.lastPosition(id)+1;
        if(reviewer.isBlank()) { unassigned(actor,id,position); return false; }
        repository.step(id,reviewer,actor,position);
        repository.notify(actor,reviewer,"REVIEW_PENDING",id,"review:"+id+":"+reviewer+":"+position);
        return true;
    }
    /** 去重键含当前步骤位置：同一缺审状态重复复核不会重复提醒。 */
    private void unassigned(Actor applicant,String id,int position) {
        var recipients=new LinkedHashSet<>(repository.unassignedRecipients(applicant.company(),applicant.id())); recipients.add(applicant.id());
        for(String recipient:recipients) repository.notify(applicant,recipient,"REVIEW_UNASSIGNED",id,"review-unassigned:"+id+":"+recipient+":"+position);
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
        result.put("reviewer_selectable",false);
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
        } else if(mode.equals("FOUNDER_PEER")) {
            throw new ApiError(409,"REVIEW_RULE_RETIRED","旧创始人互审已停用，请重新提交");
        } else if(!repository.directManager(Db.str(row,"company_id"),Db.str(row,"applicant_id")).equals(actor.id())) {
            throw ApiError.forbidden();
        }
        ReviewPolicy.reason(approve,reason);
        if(reason==null) reason="";
        repository.decideStep(steps.getFirst().get("id"),approve,reason);
        String source=mode.equals("ADMIN_MEMBERSHIP")||mode.equals("FOUNDER_PEER")?mode:"DIRECT_MANAGER";
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
        if(Db.str(row,"approval_mode").equals("FOUNDER_PEER")) throw new ApiError(409,"REVIEW_RULE_RETIRED","旧创始人互审已作废，请重新提交");
        if(!row.get("status").equals("PENDING")) throw ApiError.conflict();
        // 历史已决定步骤只作为审计保留，不阻止仍待审的申请按当前关系重新路由。
        if(Db.str(row,"kind").equals("LOG")) throw new ApiError(409,"DIRECT_CONTENT_REQUIRED","历史日报审核候选已停用");
        repository.supersedePending(id,"申请人按当前审核规则重新路由");
        String mode=mode(actor,Db.str(row,"kind"));
        if(mode==null) {
            // 用户明确继续历史申请时才应用；仍经所属模块的当前权限和目标版本校验。
            apply(actor,row); repository.status(id,"APPROVED","FOUNDER_EXEMPT");
            repository.audit(actor,"REVIEW_APPROVED",id,Map.of("status","PENDING"),Map.of("status","APPROVED","decisionSource","FOUNDER_EXEMPT"),"创始人明确继续历史申请");
            repository.notify(actor,actor.id(),"REVIEW_APPROVED",id,"review-result:"+id+":FOUNDER_EXEMPT");
        } else { repository.mode(id,mode); route(actor,id,mode); }
        repository.audit(actor,"REVIEW_REROUTED",id,Map.of("approvalMode",Db.str(row,"approval_mode")),Map.of("approvalMode",mode==null?"FOUNDER_EXEMPT":mode),"按当前有效关系替换待审步骤，保留历史决定");
        return get(actor,id);
    }

    /** 创始人互审申请的候选审核人：申请人以外的有效创始人，current 标记当前审核人。 */
    public Map<String,Object> reviewerCandidates(Actor actor,String id) {
        actor=fresh(actor);
        var row=selectable(actor,repository.request(actor.company(),id,false));
        return Map.of("items",repository.founderPeers(actor.company(),Db.str(row,"applicant_id"),repository.currentReviewer(id)));
    }

    /** 申请人更换创始人互审审核人；与决定共用申请行锁，先提交者生效。选择当前审核人时返回原结果。 */
    @Transactional
    public Map<String,Object> selectReviewer(Actor actor,String id,String reviewer,int expectedVersion) {
        actor=fresh(actor);
        var row=selectable(actor,repository.request(actor.company(),id,true));
        if(((Number)row.get("expected_version")).intValue()!=expectedVersion) throw ApiError.conflict();
        if(reviewer.equals(actor.id())||!repository.founderPeer(actor.company(),actor.id(),reviewer)) throw ApiError.bad("INVALID_REVIEWER","只能选择本公司其他在职创始人");
        String previous=repository.currentReviewer(id);
        if(reviewer.equals(previous)) return get(actor,id);
        repository.supersedePending(id,"申请人更换审核人");
        int position=(int)repository.lastPosition(id)+1;
        repository.step(id,reviewer,actor,position);
        repository.notify(actor,reviewer,"REVIEW_PENDING",id,"review:"+id+":"+reviewer+":"+position);
        var before=new HashMap<String,Object>(); before.put("reviewerId",previous.isBlank()?null:previous);
        repository.audit(actor,"REVIEW_REVIEWER_CHANGED",id,before,Map.of("reviewerId",reviewer),"申请人指定创始人审核人");
        return get(actor,id);
    }
    private Map<String,Object> selectable(Actor actor,Map<String,Object> row) {
        if(!actor.id().equals(row.get("applicant_id"))) throw ApiError.forbidden();
        if(!Db.str(row,"status").equals("PENDING")) throw ApiError.conflict();
        throw new ApiError(409,"REVIEWER_SELECTION_UNSUPPORTED","审核人由直属关系确定，不支持更换");
    }

    /**
     * 人员变更生效后，在同一事务内复核本公司其他待审申请：当前步骤失效或模式不再适用时作废并重新路由，
     * 仍无审核人则提醒。正被其他事务锁定的申请跳过，由该事务按最新关系校验；不应用任何候选。
     */
    void reconcile(Actor actor,String exclude) {
        for(String id:repository.pendingIds(actor.company())) {
            if(id.equals(exclude)) continue;
            var row=repository.lockPending(actor.company(),id);
            if(row==null) continue;
            Actor applicant=repository.actor(actor.company(),Db.str(row,"applicant_id"));
            String kind=Db.str(row,"kind"),current=Db.str(row,"approval_mode");
            if(current.equals("FOUNDER_PEER")) continue; // 已由前向迁移作废，旧候选不得重新路由。
            if(!kind.equals("MEMBERSHIP")&&(!applicant.status().equals("ACTIVE")||applicant.mustChange())) continue;
            // 仅剩一位创始人时不自动免审：保持原模式，等待申请人显式 reroute。
            String desired=Objects.requireNonNullElse(mode(applicant,kind),current);
            if(desired.equals(current)&&!repository.currentReviewerView(id).isEmpty()) continue;
            boolean hadStep=!repository.pending(id).isEmpty();
            repository.supersedePending(id,"组织变更后审核人失效");
            if(!desired.equals(current)) repository.mode(id,desired);
            boolean assigned=route(applicant,id,desired);
            if(assigned||hadStep||!desired.equals(current))
                repository.audit(actor,"REVIEW_AUTO_REROUTED",id,Map.of("approvalMode",current),Map.of("approvalMode",desired,"assigned",assigned),"组织变更后按当前规则重新分配审核人");
        }
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
        // 人员停用、改角色、改直属上级或新增管理员审核人会改变其他待审申请的有效审核人，在同一事务内重新分配。
        if(kind.equals("USER")||kind.equals("REVIEWER")) reconcile(approver,Db.str(row,"id"));
    }
}
