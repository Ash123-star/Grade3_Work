package cn.workpanel.module.organization.controller;

import cn.workpanel.Actor;
import cn.workpanel.Db;
import cn.workpanel.module.organization.application.OrganizationApplicationService;
import cn.workpanel.module.organization.application.OrganizationValidation;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 组织 HTTP 适配器：身份、请求与响应映射；所有业务及 SQL 通过应用服务。 */
@RestController
@RequestMapping("/api/organization")
public class OrganizationController {
    private final OrganizationApplicationService service;
    public OrganizationController(OrganizationApplicationService service) { this.service = service; }
    /** 有效已激活账号的授权组织树，users 保留 items/total/nextCursor 格式，返回完整范围；越权403，无版本要求。 */
    @GetMapping public Map<String, Object> tree(HttpServletRequest request) { return service.tree(Actor.current(request)); }
    /** 同公司部门 id/name 目录，不包含人员数据；已激活账号，无版本/幂等键要求。 */
    @GetMapping("/departments") public List<Map<String, Object>> departments(HttpServletRequest request) { return service.departments(Actor.current(request)); }
    /** 当前有效账号组织范围内团队目录，返回id/name/department_id/version；沿用组织树范围，越权不返回。只读，无分页、幂等键或版本要求。 */
    @GetMapping("/teams") public List<Map<String, Object>> teams(HttpServletRequest request) { return service.teams(Actor.current(request)); }
    /** PENDING 员工提交 departmentId/version/reason 归属申请；存在待审409、无效部门404；审核后生效。 */
    @PostMapping("/membership-application") public Map<String, Object> membership(HttpServletRequest request, @RequestBody Map<String, Object> body) { return service.membership(Actor.current(request), body); }
    /** 管理员读取生效审核策略与 version；非管理员403；只读幂等。 */
    @GetMapping("/review-policy") public Map<String, Object> policy(HttpServletRequest request) { return service.policy(Actor.current(request)); }
    /** 管理员提交 AI 长期授权开关、期限与数量限制及 version/reason；直属单级审核后生效。退役的 taskTeamReview/taskDepartmentReview 字段返回400。 */
    @PostMapping("/review-policy/revisions") public Map<String, Object> policyRevision(HttpServletRequest request, @RequestBody Map<String, Object> body) { return service.policyRevision(Actor.current(request), body); }
    /** 已激活账号读取人员：search/dispatch/cursor/limit；dispatch要求派发资格；分页无效400、越权403。
     * 返回人员及participatingTaskCount/activeTaskCount（当前调用人任务权限内，未结束排除ACCEPTED/ARCHIVED/WITHDRAWN）、
     * todayLogStatus（SUBMITTED/MISSING/UNKNOWN）和上海业务日summaryDate；只统计已提交日志，不披露他人草稿。
     * 只读分页，无版本和幂等键要求；每次读取实时计算，不保存重复计数字段。 */
    @GetMapping("/people") public Map<String, Object> people(HttpServletRequest request, @RequestParam(defaultValue = "") String search,
            @RequestParam(defaultValue = "false") boolean dispatch, @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "30") int limit) {
        return service.people(Actor.current(request), search, dispatch, cursor, limit);
    }
    /** ACTIVE 非复核人申请公司复核职责：version/reason；已具备409、无效400；当前直属上级批准，员工角色不改变；此职责不授予多级审核权限。 */
    @PostMapping("/reviewer-application") public Map<String, Object> reviewer(HttpServletRequest request, @RequestBody Map<String, Object> body) { return service.reviewer(Actor.current(request), body); }
    /** 管理员申请人员变更：version/reason及组织/角色/状态字段；非法400、范围外404；审核通过前旧值有效，最终版本冲突409。
     * 创建候选不采用幂等键；重复候选仍在最终版本校验时解决冲突。 */
    @PostMapping("/users/{id}/revisions") public Map<String, Object> revise(HttpServletRequest request, @PathVariable String id, @RequestBody Map<String, Object> body) { return service.revise(Actor.current(request), id, body); }
    /** 管理员提交 departments/teams 候选：id/name/departmentId/version/reason；新建version=0，更新需现有版本；非法400/不存在404，最终冲突409。 */
    @PostMapping("/{kind}/revisions") public Map<String, Object> unit(HttpServletRequest request, @PathVariable String kind, @RequestBody Map<String, Object> body) { return service.unit(Actor.current(request), kind, body); }
    /** 管理员分页审计：cursor/limit，返回items/total/nextCursor；非法400、越权403；只读无版本。 */
    @GetMapping("/audit") public Map<String, Object> audit(HttpServletRequest request, @RequestParam(defaultValue = "0") int cursor, @RequestParam(defaultValue = "30") int limit) { return service.audit(Actor.current(request), cursor, limit); }
    /** ADMIN只读任务审计：可选taskId及cursor/limit；返回items/total/nextCursor，范围外ID返回空。非法分页400、非管理员403；无版本/幂等键，保留历史前后值。 */
    @GetMapping("/task-audit") public Map<String,Object> taskAudit(HttpServletRequest request,@RequestParam(required=false) String taskId,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) { return service.taskAudit(Actor.current(request),taskId,cursor,limit); }
    /** 兼容旧审核应用调用点；组织验证统一由应用验证器维护。 */
    public static void validateUser(Db db, String company, String id, Map<String, Object> candidate) { OrganizationValidation.validateUser(db, company, id, candidate); }
}
