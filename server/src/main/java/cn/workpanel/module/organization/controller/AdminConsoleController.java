package cn.workpanel.module.organization.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.organization.application.AdminConsoleService;
import io.swagger.v3.oas.annotations.Operation;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 简易后台v1；所有接口需要当前ACTIVE ADMIN、已改初始密码；错误含code/traceId。 */
@RestController
@RequestMapping("/api/admin/console")
public class AdminConsoleController {
    private final AdminConsoleService service;
    public AdminConsoleController(AdminConsoleService service) { this.service=service; }
    /** 本公司员工含停用，search<=100字/cursor>=0/limit 1..100；items/total/nextCursor，不含哈希。只读幂等；400/401/403。 */
    @Operation(summary="管理员分页查询员工（含停用账号）")
    @GetMapping("/employees") public Map<String,Object> employees(HttpServletRequest r,@RequestParam(defaultValue="") String search,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="20") int limit) { return service.employees(Actor.current(r),search,cursor,limit); }
    /** account/password/phone/name/departmentId必填，固定EMPLOYEE/ACTIVE/首次改密；返回脱敏人员，无幂等键，重复409，不自动重试；跨公司部门404/未知字段400。 */
    @Operation(summary="管理员直接创建员工账号",description="固定ACTIVE/EMPLOYEE，首次登录改密；账号或手机号重复409，禁止角色和公司注入，不返回密码或哈希。")
    @PostMapping("/employees") public Map<String,Object> create(HttpServletRequest r,@RequestBody Map<String,Object> body) { return service.create(Actor.current(r),body); }
    /** 本公司部门id/name，仅ADMIN；无分页/版本/幂等键，401/403。 */
    @GetMapping("/departments") public List<Map<String,Object>> departments(HttpServletRequest r) { return service.departments(Actor.current(r)); }
    /** 姓名/部门/ACTIVE或DISABLED候选，必填version/reason；返回审核申请，审核前旧值有效。无幂等键；400/403/404/409；不允许改角色。 */
    @PostMapping("/employees/{id}/revisions") public Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> body) { return service.reviseEmployee(Actor.current(r),id,body); }
    /** 本公司事项含已撤下，cursor/limit分页，返回items/total/nextCursor；只读幂等、无版本，非法分页400。 */
    @GetMapping("/priorities") public Map<String,Object> priorities(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="20") int limit) { return service.priorities(Actor.current(r),cursor,limit); }
    /** title/text/pinned/archived/position/version/reason，修改额外id；新建version=0；返回COMPANY_ITEM申请。无幂等键；最终审核版本冲突409/十项限制400/自审403。 */
    @PostMapping("/priorities/revisions") public Map<String,Object> priority(HttpServletRequest r,@RequestBody Map<String,Object> body) { return service.revisePriority(Actor.current(r),body); }
    /** 本人申请或分配审核，cursor/limit分页items/total/nextCursor；仅ADMIN，沿用审核范围，只读无版本。 */
    @GetMapping("/reviews") public Map<String,Object> reviews(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="20") int limit) { return service.reviews(Actor.current(r),cursor,limit); }
    /** 申请详情含候选/steps；本人或有效分配审核人，越权403/未知404；只读幂等。 */
    @GetMapping("/reviews/{id}") public Map<String,Object> review(HttpServletRequest r,@PathVariable String id) { return service.review(Actor.current(r),id); }
    /** approve/reason/expectedVersion，驳回原因必填；沿用直属独立审核，自审403/冲突409，重复不自动重放，无幂等键。 */
    @PostMapping("/reviews/{id}/decision") public Map<String,Object> decide(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> body) { return service.decide(Actor.current(r),id,body); }
}
