package cn.workpanel.module.customer.application;

import cn.workpanel.*;
import cn.workpanel.module.customer.domain.*;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.util.*;

/** C 侧客户/会员/权益用例；首版只允许 ACTIVE ADMIN，B 确认角色后可在此集中放开。 */
@Service
public class CustomerService {
    private final CustomerRepository repo;
    public CustomerService(CustomerRepository repo) { this.repo=repo; }
    private Actor admin(Actor request) {
        Actor a=repo.current(request);a.requireAdmin();
        if(!a.status().equals("ACTIVE")) throw ApiError.forbidden();
        if(a.mustChange()) throw new ApiError(403,"PASSWORD_CHANGE_REQUIRED","首次登录请修改密码");
        return a;
    }
    private static String search(String value) {
        String s=value==null?"":value.trim();
        if(s.length()>100) throw ApiError.bad("INVALID_SEARCH","关键词最多100字");
        return s;
    }
    public Map<String,Object> list(Actor request,String search,String kind,int cursor,int limit) {
        Actor a=admin(request);Business.page(cursor,limit);
        String k=kind==null?"":kind.trim().toUpperCase();
        if(!k.isEmpty()&&!k.equals("INDIVIDUAL")&&!k.equals("ENTERPRISE")) throw ApiError.bad("INVALID_KIND","客户类型无效");
        return repo.list(a,search(search),k,cursor,limit);
    }
    @Transactional public Map<String,Object> create(Actor request,Map<String,Object> body) {
        Actor a=admin(request);var draft=CustomerDraft.parse(body,false);
        try { var created=repo.create(a,draft);repo.audit(a,"CUSTOMER_CREATED",Db.str(created,"id"),null,created,"");return created; }
        catch(DuplicateKeyException e) { throw new ApiError(409,"CUSTOMER_EXTERNAL_CONFLICT","商城外部ID已被其他客户使用"); }
    }
    public Map<String,Object> detail(Actor request,String id) {
        Actor a=admin(request);
        var result=new LinkedHashMap<String,Object>();
        result.put("customer",repo.get(a,id));
        result.put("membership",repo.membership(a,id));
        result.put("benefits",repo.benefits(a,id));
        result.put("progress",repo.progress(a,id));
        return result;
    }
    public Map<String,Object> byExternal(Actor request,String externalId) {
        Actor a=admin(request);
        String key=externalId==null?"":externalId.trim();
        if(key.isEmpty()||key.length()>200) throw ApiError.bad("INVALID_EXTERNAL_ID","商城外部ID无效");
        return repo.byExternal(a,key);
    }
    @Transactional public Map<String,Object> update(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);var before=repo.get(a,id);var draft=CustomerDraft.parse(body,true);
        try { var updated=repo.update(a,id,draft);repo.audit(a,"CUSTOMER_UPDATED",id,before,updated,"");return updated; }
        catch(DuplicateKeyException e) { throw new ApiError(409,"CUSTOMER_EXTERNAL_CONFLICT","商城外部ID已被其他客户使用"); }
    }
    @Transactional public Map<String,Object> membership(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);repo.get(a,id);var before=repo.membership(a,id);var draft=MembershipDraft.parse(body);
        if(before!=null&&draft.version()!=((Number)before.get("version")).intValue()) throw ApiError.conflict();
        if(before==null&&draft.version()!=0) throw ApiError.conflict();
        try {
            var saved=repo.upsertMembership(a,id,draft);
            repo.audit(a,"CUSTOMER_MEMBERSHIP_UPDATED",id,before,saved,"");
            return saved;
        } catch(DuplicateKeyException e) { throw new ApiError(409,"MALL_MEMBER_CONFLICT","商城会员ID已绑定其他客户"); }
    }
    public List<Map<String,Object>> benefits(Actor request,String id) {
        Actor a=admin(request);repo.get(a,id);return repo.benefits(a,id);
    }
    public List<Map<String,Object>> redemptions(Actor request,String id,String benefitId) {
        Actor a=admin(request);repo.get(a,id);repo.benefit(a,id,benefitId,false);return repo.redemptions(a,benefitId);
    }
    @Transactional public Map<String,Object> createBenefit(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);repo.get(a,id);var draft=BenefitDraft.parse(body);
        var created=repo.createBenefit(a,id,draft);
        repo.audit(a,"CUSTOMER_BENEFIT_CREATED",Db.str(created,"id"),null,created,"");
        return created;
    }
    @Transactional public Map<String,Object> redeem(Actor request,String customerId,String benefitId,Map<String,Object> body,String key) {
        Actor a=admin(request);
        if(key==null||!key.matches("[A-Za-z0-9:_.-]{1,128}")) throw ApiError.bad("INVALID_IDEMPOTENCY_KEY","需要1–128位Idempotency-Key");
        Db.fields(body,"note");
        String note=body.get("note")==null?"":Db.str(body,"note").trim();
        if(note.length()>500) throw ApiError.bad("INVALID_NOTE","核销备注最多500字");
        var customer=repo.get(a,customerId);
        var benefit=repo.benefit(a,customerId,benefitId,true);
        var existing=repo.redemptionByKey(a,benefitId,key);
        if(existing!=null) return redemptionResult(existing);
        if("ARCHIVED".equals(Db.str(customer,"status"))) throw new ApiError(409,"CUSTOMER_ARCHIVED","客户已归档");
        if(!"ACTIVE".equals(Db.str(benefit,"status"))) throw new ApiError(409,"BENEFIT_DISABLED","权益已停用");
        LocalDate today=LocalDate.now(ZoneId.of("Asia/Shanghai"));
        LocalDate from=LocalDate.parse(Db.str(benefit,"validFrom"));
        LocalDate to=LocalDate.parse(Db.str(benefit,"validTo"));
        if(today.isBefore(from)||today.isAfter(to)) throw new ApiError(409,"BENEFIT_EXPIRED","权益不在有效期内");
        Long max=benefit.get("maxUses") instanceof Number limit?limit.longValue():null;
        long used=repo.redemptionCount(a,benefitId);
        if(max!=null&&used>=max) throw new ApiError(409,"BENEFIT_EXHAUSTED","权益可用次数已用完");
        var receipt=repo.insertRedemption(a,customerId,benefitId,key,note,used+1,max==null?null:max-used-1);
        repo.audit(a,"CUSTOMER_BENEFIT_REDEEMED",benefitId,null,receipt.redemption(),"");
        return redemptionResult(receipt);
    }
    private static Map<String,Object> redemptionResult(CustomerRepository.RedemptionReceipt receipt) {
        var result=new LinkedHashMap<String,Object>();
        result.put("redemption",receipt.redemption());
        result.put("used",receipt.used());
        result.put("remaining",receipt.remaining());
        return result;
    }
    public List<Map<String,Object>> progress(Actor request,String id) {
        Actor a=admin(request);repo.get(a,id);return repo.progress(a,id);
    }
    @Transactional public Map<String,Object> addProgress(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);repo.get(a,id);
        Db.fields(body,"stage","note");
        String stage=Db.required(body,"stage");
        if(stage.length()>100) throw ApiError.bad("INVALID_STAGE","服务阶段最多100字");
        String note=body.get("note")==null?"":Db.str(body,"note").trim();
        if(note.length()>1000) throw ApiError.bad("INVALID_NOTE","服务进度说明最多1000字");
        var saved=repo.addProgress(a,id,stage,note);
        repo.audit(a,"CUSTOMER_PROGRESS_ADDED",Db.str(saved,"id"),null,saved,"");
        return saved;
    }
}
