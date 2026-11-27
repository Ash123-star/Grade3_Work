package cn.workpanel.module.customer.application;

import cn.workpanel.*;
import cn.workpanel.module.customer.domain.*;
import cn.workpanel.shared.application.CommandKeys;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.util.*;
import java.util.function.Supplier;

/** C 侧客户/会员/权益用例；首版只允许 ACTIVE ADMIN，B 确认角色后可在此集中放开。 */
@Service
public class CustomerService {
    private final CustomerRepository repo;
    private final CommandKeys keys;
    public CustomerService(CustomerRepository repo,CommandKeys keys) { this.repo=repo;this.keys=keys; }
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
        String k=kind==null?"":kind.trim().toUpperCase(Locale.ROOT);
        if(!k.isEmpty()&&!k.equals("INDIVIDUAL")&&!k.equals("ENTERPRISE")) throw ApiError.bad("INVALID_KIND","客户类型无效");
        return repo.list(a,search(search),k,cursor,limit);
    }
    @Transactional public Map<String,Object> create(Actor request,Map<String,Object> body,String key) {
        Actor a=admin(request);var draft=CustomerDraft.parse(body,false);
        if(body.containsKey("confirmDuplicate")&&(!(body.get("confirmDuplicate") instanceof Boolean)||key==null))
            throw ApiError.bad("INVALID_DUPLICATE_CONFIRMATION","确认重复建档须提交有效请求标识");
        if(key==null) return persistCustomer(a,draft,false,false);
        validateKey(key);
        var receipt=keys.execute(a,"CUSTOMER_CREATE",key,body,()->Map.of(
            "id",Db.str(persistCustomer(a,draft,true,Boolean.TRUE.equals(body.get("confirmDuplicate"))),"id")));
        return repo.get(a,Db.str(receipt,"id"));
    }
    private Map<String,Object> persistCustomer(Actor a,CustomerDraft draft,boolean checkDuplicate,boolean confirmed) {
        repo.lockProfileWrites(a);
        if(checkDuplicate&&!confirmed&&repo.hasSimilarActiveProfile(a,draft))
            throw new ApiError(409,"CUSTOMER_POSSIBLE_DUPLICATE","已有同名或联系方式相同的客户");
        if(draft.ownerId()!=null) repo.requireActiveOwner(a,draft.ownerId());
        try {
            var created=repo.create(a,draft,draft.contacts()==null?List.of():contactIds(draft.contacts(),Set.of()));
            repo.audit(a,"CUSTOMER_CREATED",Db.str(created,"id"),null,created,confirmed?"已确认疑似重复":"");
            return created;
        } catch(DuplicateKeyException e) { throw new ApiError(409,"CUSTOMER_EXTERNAL_CONFLICT","商城外部ID已被其他客户使用"); }
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
    /** 同公司管理员查询当前客户明确绑定的商城会员 ID。只读，客户不可见时返回 404。 */
    public Optional<String> mallMemberId(Actor request, String customerId) {
        Actor actor = admin(request);
        repo.get(actor, customerId);
        return Optional.ofNullable(repo.membership(actor, customerId))
                .map(membership -> Db.str(membership, "mallMemberId"));
    }
    @Transactional public Map<String,Object> update(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);var draft=CustomerDraft.parse(body,true);
        repo.lockProfileWrites(a);
        var before=repo.get(a,id);
        if(!Objects.equals(before.get("version"),draft.version())) throw ApiError.conflict();
        if(draft.ownerId()!=null&&!Objects.equals(draft.ownerId(),before.get("ownerId"))) repo.requireActiveOwner(a,draft.ownerId());
        var priorContacts=before.get("contacts") instanceof List<?> prior?prior:List.of();
        var contacts=draft.contacts();
        if(contacts==null&&draft.kind().equals("INDIVIDUAL")&&!priorContacts.isEmpty())
            throw ApiError.bad("INVALID_CONTACTS","变更为个人客户前须明确清空企业联系人");
        if(contacts!=null) {
            var ids=new HashSet<String>();
            for(Object prior:priorContacts) if(prior instanceof Map<?,?> row&&row.get("id") instanceof String contactId) ids.add(contactId);
            contacts=contactIds(contacts,ids);
        }
        try { var updated=repo.update(a,id,draft,contacts);repo.audit(a,"CUSTOMER_UPDATED",id,before,updated,"");return updated; }
        catch(DuplicateKeyException e) { throw new ApiError(409,"CUSTOMER_EXTERNAL_CONFLICT","商城外部ID已被其他客户使用"); }
    }
    private static List<CustomerDraft.Contact> contactIds(List<CustomerDraft.Contact> contacts,Set<String> existing) {
        return contacts.stream().map(contact->{
            if(contact.id().isEmpty()) return new CustomerDraft.Contact("con_"+Db.id(),contact.name(),contact.role(),contact.phone(),contact.email());
            if(!existing.contains(contact.id())) throw ApiError.bad("INVALID_CONTACTS","联系人不属于当前客户");
            return contact;
        }).toList();
    }
    @Transactional public Map<String,Object> membership(Actor request,String id,Map<String,Object> body) {
        Actor a=admin(request);requireOpen(repo.lock(a,id));
        var before=repo.membership(a,id);var draft=MembershipDraft.parse(body);
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
    @Transactional public Map<String,Object> createBenefit(Actor request,String id,Map<String,Object> body,String key) {
        Actor a=admin(request);var customer=repo.lock(a,id);var draft=BenefitDraft.parse(body);
        Supplier<Map<String,Object>> action=()->{
            requireOpen(customer);
            var created=repo.createBenefit(a,id,draft);
            repo.audit(a,"CUSTOMER_BENEFIT_CREATED",Db.str(created,"id"),null,created,"");
            return created;
        };
        if(key==null) return action.get();
        return repo.benefit(a,id,appendOnce(a,id,body,key,"CUSTOMER_BENEFIT_CREATE",action),false);
    }
    @Transactional public Map<String,Object> redeem(Actor request,String customerId,String benefitId,Map<String,Object> body,String key) {
        Actor a=admin(request);
        validateKey(key);
        Db.fields(body,"note");
        String note=body.get("note")==null?"":Db.str(body,"note").trim();
        if(note.length()>500) throw ApiError.bad("INVALID_NOTE","核销备注最多500字");
        var customer=repo.lock(a,customerId);
        var benefit=repo.benefit(a,customerId,benefitId,true);
        var existing=repo.redemptionByKey(a,benefitId,key);
        if(existing!=null) return redemptionResult(existing);
        requireOpen(customer);
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
    @Transactional public Map<String,Object> addProgress(Actor request,String id,Map<String,Object> body,String key) {
        Actor a=admin(request);var customer=repo.lock(a,id);
        Db.fields(body,"stage","note");
        String stage=Db.required(body,"stage");
        if(stage.length()>100) throw ApiError.bad("INVALID_STAGE","服务阶段最多100字");
        String note=body.get("note")==null?"":Db.str(body,"note").trim();
        if(note.length()>1000) throw ApiError.bad("INVALID_NOTE","服务进度说明最多1000字");
        Supplier<Map<String,Object>> action=()->{
            requireOpen(customer);
            var saved=repo.addProgress(a,id,stage,note);
            repo.audit(a,"CUSTOMER_PROGRESS_ADDED",Db.str(saved,"id"),null,saved,"");
            return saved;
        };
        if(key==null) return action.get();
        return repo.progressEntry(a,id,appendOnce(a,id,body,key,"CUSTOMER_PROGRESS_ADD",action));
    }
    private String appendOnce(Actor a,String id,Map<String,Object> body,String key,String operation,Supplier<Map<String,Object>> action) {
        validateKey(key);
        return Db.str(keys.execute(a,operation,key,Map.of("customerId",id,"body",body),
            ()->Map.of("id",Db.str(action.get(),"id"))),"id");
    }
    private static void requireOpen(Map<String,Object> customer) {
        if("ARCHIVED".equals(Db.str(customer,"status"))) throw new ApiError(409,"CUSTOMER_ARCHIVED","客户已归档");
    }
    private static void validateKey(String key) {
        if(key==null||!key.matches("[A-Za-z0-9:_.-]{1,128}"))
            throw ApiError.bad("INVALID_IDEMPOTENCY_KEY","需要1–128位Idempotency-Key");
    }
}
