package cn.workpanel.module.delivery.controller;

import cn.workpanel.*;
import cn.workpanel.module.delivery.application.OfflineDeliveryService;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/offline-deliveries")
public class OfflineDeliveryController {
    private final OfflineDeliveryService service;

    public OfflineDeliveryController(OfflineDeliveryService service) { this.service = service; }

    private static void query(HttpServletRequest request, String... keys) {
        var allowed = Set.of(keys);
        request.getParameterMap().forEach((key, values) -> {
            if (!allowed.contains(key) || values.length != 1) throw ApiError.bad("UNKNOWN_FIELD", "未知或重复查询参数");
        });
    }

    /** 本公司管理员按客户或员工分页读取活动及交付状态，400 参数错误、404 关联不可见；无需版本或幂等键。 */
    @Operation(operationId = "listOfflineDeliveries", summary = "按客户或员工读取线下业务",
            description = "仅在职已改密 ADMIN；customerId/employeeId 二选一，pendingOnly 默认 false；返回 items/total/nextCursor。")
    @GetMapping
    public Map<String, Object> list(HttpServletRequest r, @RequestParam(defaultValue = "") String customerId,
                                    @RequestParam(defaultValue = "") String employeeId,
                                    @RequestParam(defaultValue = "false") boolean pendingOnly,
                                    @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "20") int limit) {
        query(r, "customerId", "employeeId", "pendingOnly", "cursor", "limit");
        return service.list(Actor.current(r), customerId, employeeId, pendingOnly, cursor, limit);
    }

    /** 在职已改密管理员查询同公司人员的 id/姓名/状态；400 参数错误、403 越权；无需版本或幂等键。 */
    @Operation(operationId = "listOfflineDeliveryEmployees", summary = "查询线下业务关联员工",
            description = "仅在职已改密 ADMIN；按姓名搜索及分页，可用 activeOnly 筛在职；不返回联系方式。")
    @GetMapping("/employees")
    public Map<String, Object> employees(HttpServletRequest r, @RequestParam(defaultValue = "") String search,
                                         @RequestParam(defaultValue = "true") boolean activeOnly,
                                         @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "20") int limit) {
        query(r, "search", "activeOnly", "cursor", "limit");
        return service.employees(Actor.current(r), search, activeOnly, cursor, limit);
    }

    /** 管理员读取同公司正式记录及待审操作摘要；不存在或跨公司 404；无需版本或幂等键。 */
    @Operation(operationId = "getOfflineDelivery", summary = "读取线下业务详情",
            description = "返回两类正式状态、版本、时间及待审摘要；跨公司返回 404。")
    @GetMapping("/{id}")
    public Map<String, Object> get(HttpServletRequest r, @PathVariable String id) {
        query(r);
        return service.get(Actor.current(r), id);
    }

    /** 管理员登记业务，初始活动待结束且服务待交付；201 返回 id/version，无输入版本；非法400、客户不可见404、键冲突409。 */
    @Operation(operationId = "createOfflineDelivery", summary = "登记线下业务",
            description = "customerId/kind/title/businessDate/ownerId/participants；须提供 Idempotency-Key，重放返回原回执。")
    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Map<String, Object> create(HttpServletRequest r, @RequestHeader("Idempotency-Key") String key,
                                      @RequestBody Map<String, Object> body) {
        query(r);
        return service.create(Actor.current(r), body, key);
    }

    /** 管理员申请资料修订、结束或交付；须用当前 version、理由和幂等键；202 返回 reviewId，非法400、越权403、版本或状态冲突409。 */
    @Operation(operationId = "submitOfflineDeliveryChange", summary = "提交线下业务变更审核",
            description = "action=EDIT/END_ACTIVITY/CONFIRM_DELIVERY；EDIT 需完整资料；独立审批前正式状态不变。")
    @PostMapping("/{id}/changes") @ResponseStatus(HttpStatus.ACCEPTED)
    public Map<String, Object> submit(HttpServletRequest r, @PathVariable String id,
                                      @RequestHeader("Idempotency-Key") String key, @RequestBody Map<String, Object> body) {
        query(r);
        return service.submit(Actor.current(r), id, body, key);
    }
}
