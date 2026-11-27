package cn.workpanel.module.customer.controller;

import cn.workpanel.*;
import cn.workpanel.module.customer.application.CustomerService;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 二期 C：统一客户档案、商城会员、年卡/权益和服务进度。首版仅 ACTIVE ADMIN；外部ID供商城联调。 */
@RestController
@RequestMapping("/api/customers")
public class CustomerController {
    private final CustomerService service;
    public CustomerController(CustomerService service) { this.service=service; }
    private static void query(HttpServletRequest r,String... names) {
        var allowed=Set.of(names);
        r.getParameterMap().forEach((name,values)->{if(!allowed.contains(name)||values.length!=1) throw ApiError.bad("UNKNOWN_FIELD","未知或重复查询参数");});
    }
    /** 本公司客户分页；search匹配姓名/电话/邮箱/外部ID，kind可选，cursor>=0，limit 1–100。 */
    @Operation(operationId="listCustomers",summary="分页查询客户",description="仅ADMIN；search最多100字，kind=INDIVIDUAL/ENTERPRISE；items/total/nextCursor；不跨公司。")
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="") String search,@RequestParam(defaultValue="") String kind,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="20") int limit) {
        query(r,"search","kind","cursor","limit");return service.list(Actor.current(r),search,kind,cursor,limit);
    }
    /** 本公司 ADMIN 建档。带幂等键时检测疑似重复；同键同内容返回已建档案，同键异内容 409。不需版本。 */
    @Operation(operationId="createCustomer",summary="新建客户档案",description="kind/name必填；phone/email/externalId/note/ownerId/contacts可选；externalId公司内唯一；仅ADMIN。正式手帐提交Idempotency-Key，疑似重复409，核对后以confirmDuplicate=true提交。")
    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Map<String,Object> create(HttpServletRequest r,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestBody Map<String,Object> body) {
        query(r);return service.create(Actor.current(r),body,key);
    }
    /** 商城外部ID反查统一客户ID；供E同步会员/订单时使用。 */
    @Operation(operationId="customerByExternalId",summary="按商城外部ID查询客户",description="仅ADMIN；externalId公司内唯一；不存在404；不跨公司。")
    @GetMapping("/external/{externalId}") public Map<String,Object> byExternal(HttpServletRequest r,@PathVariable String externalId) {
        query(r);return service.byExternal(Actor.current(r),externalId);
    }
    /** 客户详情含会员、权益列表和服务进度；D/E通过id关联。 */
    @Operation(operationId="customerDetail",summary="读取客户详情",description="仅ADMIN；返回customer/membership/benefits/progress；不存在或跨公司404。")
    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) {
        query(r);return service.detail(Actor.current(r),id);
    }
    /** 更新客户档案，必须带当前version；externalId冲突409。 */
    @Operation(operationId="updateCustomer",summary="更新客户档案",description="全量kind/name/phone/email/externalId/note/status和version；省略ownerId/contacts保留原值；仅ADMIN；版本或外部ID冲突409。")
    @PutMapping("/{id}") public Map<String,Object> update(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> body) {
        query(r);return service.update(Actor.current(r),id,body);
    }
    /** 绑定或更新商城会员；version=0表示首次绑定，已有会员必须带当前version。 */
    @Operation(operationId="upsertCustomerMembership",summary="绑定/更新商城会员",description="mallMemberId必填且公司内唯一；level/joinedAt/expiresAt/status可选；首次version=0，更新带当前version；仅ADMIN。")
    @PutMapping("/{id}/membership") public Map<String,Object> membership(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> body) {
        query(r);return service.membership(Actor.current(r),id,body);
    }
    /** 客户权益列表（年卡/商城会员等），含有效期与剩余次数所需字段。 */
    @Operation(operationId="listCustomerBenefits",summary="读取客户权益",description="仅ADMIN；返回该客户全部权益；不跨公司。")
    @GetMapping("/{id}/benefits") public List<Map<String,Object>> benefits(HttpServletRequest r,@PathVariable String id) {
        query(r);return service.benefits(Actor.current(r),id);
    }
    /** 本公司管理员发放权益；不需要版本，归档拒绝新增，同键同请求返回已有权益，异内容409。 */
    @Operation(operationId="createCustomerBenefit",summary="发放客户权益",description="kind=ANNUAL_CARD/MALL_MEMBER/OTHER；name/validFrom/validTo必填；maxUses可选1–100000；仅ADMIN；支持Idempotency-Key；已归档或键冲突409。")
    @PostMapping("/{id}/benefits") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,Object> createBenefit(HttpServletRequest r,@PathVariable String id,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestBody Map<String,Object> body) {
        query(r);return service.createBenefit(Actor.current(r),id,body,key);
    }
    /** 权益核销历史；用于查年卡有效期与使用记录，按时间倒序。 */
    @Operation(operationId="listCustomerBenefitRedemptions",summary="读取权益核销历史",description="仅ADMIN；校验权益属于该客户；按核销时间倒序；不跨公司。")
    @GetMapping("/{id}/benefits/{benefitId}/redemptions") public List<Map<String,Object>> redemptions(HttpServletRequest r,@PathVariable String id,@PathVariable String benefitId) {
        query(r);return service.redemptions(Actor.current(r),id,benefitId);
    }
    /** 权益核销；同一Idempotency-Key重复提交返回原结果，不重复扣次；过期/停用/次数用完409。 */
    @Operation(operationId="redeemCustomerBenefit",summary="核销客户权益",description="必须提供Idempotency-Key，note可选最多500字；同一key同权益只记一次；失效或超次409；仅ADMIN。")
    @PostMapping("/{id}/benefits/{benefitId}/redemptions") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,Object> redeem(HttpServletRequest r,@PathVariable String id,@PathVariable String benefitId,@RequestHeader(value="Idempotency-Key") String key,@RequestBody(required=false) Map<String,Object> body) {
        query(r);return service.redeem(Actor.current(r),id,benefitId,body==null?Map.of():body,key);
    }
    /** 会员服务进度列表；按时间倒序。 */
    @Operation(operationId="listCustomerProgress",summary="读取会员服务进度",description="仅ADMIN；按创建时间倒序；不跨公司。")
    @GetMapping("/{id}/progress") public List<Map<String,Object>> progress(HttpServletRequest r,@PathVariable String id) {
        query(r);return service.progress(Actor.current(r),id);
    }
    /** 本公司管理员追加服务进度；不需要版本，归档拒绝新增，同键同请求返回已有进度，异内容409。 */
    @Operation(operationId="addCustomerProgress",summary="追加会员服务进度",description="stage 1–100字，note最多1000字；仅ADMIN；无审核链；支持Idempotency-Key；已归档或键冲突409。")
    @PostMapping("/{id}/progress") @ResponseStatus(HttpStatus.CREATED)
    public Map<String,Object> addProgress(HttpServletRequest r,@PathVariable String id,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestBody Map<String,Object> body) {
        query(r);return service.addProgress(Actor.current(r),id,body,key);
    }
}
