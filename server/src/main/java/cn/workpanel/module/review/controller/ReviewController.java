package cn.workpanel.module.review.controller;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import cn.workpanel.module.review.application.ReviewApplicationService;
import cn.workpanel.module.review.domain.ReviewPolicy;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

/** 审核 HTTP 适配器：不执行 SQL，实际规则和事务由审核应用服务负责。 */
@RestController
@RequestMapping("/api/reviews")
public class ReviewController {
    private final ReviewApplicationService service;
    public ReviewController(ReviewApplicationService service) { this.service = service; }
    /** 有效会话分页读取本人申请或分配给本人的审核：cursor/limit；非法400，未认证401，无版本要求。 */
    @GetMapping public Map<String, Object> list(HttpServletRequest request, @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "30") int limit) { return service.list(Actor.current(request), cursor, limit); }
    /** 本公司申请人或分配的审核人读取候选和步骤；无权限403、不存在404，无版本要求。 */
    @GetMapping("/{id}") public Map<String, Object> get(HttpServletRequest request, @PathVariable String id) { return service.get(Actor.current(request), id); }
    /** 当前直属上级或管理员成员确认人决定：approve/reason/expectedVersion；驳回须非空原因，自审403、无效400、终态或目标版本冲突409。
     * 最终审核才更新业务版本；重复决定不重放，无幂等键。 */
    @PostMapping("/{id}/decision") public Map<String, Object> decide(HttpServletRequest request, @PathVariable String id, @RequestBody Map<String, Object> body) {
        boolean approve=ReviewPolicy.decision(body);
        return service.decide(Actor.current(request), id, approve, Db.str(body, "reason"), ReviewPolicy.expectedVersion(body));
    }
    /** 申请人按当前关系重路由PENDING申请；保留已决历史。创始人明确继续非MEMBERSHIP旧申请时按当前权限/版本免审应用；该终态重复请求返回原结果。其他终态409、越权403；无幂等键。 */
    @PostMapping("/{id}/reroute") public Map<String, Object> reroute(HttpServletRequest request, @PathVariable String id) { return service.reroute(Actor.current(request), id); }
}
