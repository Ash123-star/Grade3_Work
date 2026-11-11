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
    /** 本公司申请人或分配的审核人读取候选和步骤；追加 display_references（people/labels/departments/teams 的 ID→当前名称），
     * 仅解析本申请快照中同公司的引用，不含账号字段；原始快照和审核版本语义不变。无权限403、不存在404，无版本要求，无写副作用。 */
    @GetMapping("/{id}") public Map<String, Object> get(HttpServletRequest request, @PathVariable String id) { return service.get(Actor.current(request), id); }
    /** 当前直属上级或管理员成员确认人决定：approve/reason/expectedVersion；驳回须非空原因，自审403、无效400、终态或目标版本冲突409。
     * 最终审核才更新业务版本；重复决定不重放，无幂等键。 */
    @PostMapping("/{id}/decision") public Map<String, Object> decide(HttpServletRequest request, @PathVariable String id, @RequestBody Map<String, Object> body) {
        boolean approve=ReviewPolicy.decision(body);
        return service.decide(Actor.current(request), id, approve, Db.str(body, "reason"), ReviewPolicy.expectedVersion(body));
    }
    /** 申请人按当前关系重路由PENDING申请；保留已决历史。旧FOUNDER_PEER申请已作废，不能恢复；其他历史创始人申请沿用权限/版本守卫。其他终态409、越权403；无幂等键。 */
    @PostMapping("/{id}/reroute") public Map<String, Object> reroute(HttpServletRequest request, @PathVariable String id) { return service.reroute(Actor.current(request), id); }
    /** 已停用的候选接口，保留旧客户端兼容：验证登录及申请归属后返回409；越权403，不产生写入。 */
    @GetMapping("/{id}/reviewer-candidates") public Map<String, Object> reviewerCandidates(HttpServletRequest request, @PathVariable String id) { return service.reviewerCandidates(Actor.current(request), id); }
    /** 已停用的换人接口；reviewerId/expectedVersion仍校验，合法请求返回409，无幂等副作用。直属上级由组织关系确定。 */
    @PostMapping("/{id}/reviewer") public Map<String, Object> selectReviewer(HttpServletRequest request, @PathVariable String id, @RequestBody Map<String, Object> body) {
        Db.fields(body, "reviewerId", "expectedVersion");
        return service.selectReviewer(Actor.current(request), id, Db.required(body, "reviewerId"), ReviewPolicy.expectedVersion(body));
    }
}
