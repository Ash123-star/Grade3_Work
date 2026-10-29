package cn.workpanel.module.auth.controller;

import cn.workpanel.Actor;
import cn.workpanel.Limiter;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.auth.application.AuthApplicationService;
import cn.workpanel.module.auth.application.DefaultAuthApplicationService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import java.util.*;

/** 认证 HTTP 适配器；只映射协议、认证上下文与 IP 限流，不访问数据库。 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthApplicationService service;
    private final Limiter limiter;
    public AuthController(AuthApplicationService service, Limiter limiter) { this.service = service; this.limiter = limiter; }
    /** 公开注册部门列表；无请求参数，返回 id/name；无版本或幂等键要求。 */
    @GetMapping("/departments") public List<Map<String, Object>> registrationDepartments() { return service.registrationDepartments(); }
    /** 公开注册：account/password/phone/name/departmentId；仅员工待确认，禁止 role。
     * 返回 id/role/status/reviewId/phoneVerified；非法字段 400、部门不存在 404、重复 409、限流 429。
     * 无版本；重复注册拒绝，不采用幂等键。 */
    @PostMapping("/register") public Map<String, Object> register(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        limiter.check("register:" + request.getRemoteAddr(), 10, 3600);
        return service.register(body);
    }
    /** 公开登录：account/password；返回 token/expiresAt/user；默认有效期168小时（SESSION_HOURS可覆盖），退出、改密及停用可提前撤销。错误或锁定 401，密码已验证的停用账号 403，IP 限流 429。
     * 五次失败锁十分钟；每次成功创建新会话，无版本或幂等键要求。 */
    @Operation(summary = "账号密码登录", description = "连续五次失败锁定十分钟，锁定期间不续期。未知账号与错误密码统一返回 INVALID_CREDENTIALS；成功创建新会话。")
    @ApiResponses({@ApiResponse(responseCode = "200", description = "返回 token、expiresAt 和公开 user"),
        @ApiResponse(responseCode = "400", description = "INVALID_FIELD 或 UNKNOWN_FIELD"),
        @ApiResponse(responseCode = "401", description = "INVALID_CREDENTIALS：凭据错误或账号锁定"),
        @ApiResponse(responseCode = "403", description = "ACCOUNT_DISABLED：密码正确但账号停用"),
        @ApiResponse(responseCode = "429", description = "RATE_LIMITED：IP 限流"),
        @ApiResponse(responseCode = "503", description = "LIMITER_UNAVAILABLE")})
    @PostMapping("/login") public Map<String, Object> login(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        limiter.check("login:" + request.getRemoteAddr(), 30, 60);
        return service.login(body);
    }
    /** 有效会话读取本人公开字段，不含密码/手机号/会话摘要；未认证 401；无版本要求。 */
    @GetMapping("/me") public Map<String, Object> me(HttpServletRequest request) { return service.current(context(request)); }
    /** 有效会话改密：oldPassword/newPassword；首次改密允许调用。返回 reloginRequired，撤销全部旧会话。
     * 旧密码错误 401、无效/相同新密码 400；无版本要求，旧凭证重试被拒绝。 */
    @PostMapping("/password") public Map<String, Object> change(@RequestBody Map<String, Object> body, HttpServletRequest request) { return service.changePassword(context(request), body); }
    /** 有效会话注销：无 body，返回 ok；撤销仅当前 token。数据库撤销幂等，旧 token 重试由过滤器返回 401；无版本要求。 */
    @PostMapping("/logout") public Map<String, Object> logout(HttpServletRequest request) { return service.logout(context(request), request.getHeader("Authorization").substring(7)); }
    private static ActorContext context(HttpServletRequest request) {
        Actor actor = Actor.current(request);
        return new ActorContext(actor.id(), actor.company(), actor.role(), actor.department(), actor.team(), actor.status().equals("ACTIVE"), actor.dispatch(), actor.reviewer(), Set.of());
    }
    /** 兼容已有 dashboard 调用；字段筛选规则由认证用例实现维护。 */
    public static Map<String, Object> publicUser(Map<String, Object> user) { return DefaultAuthApplicationService.publicUser(user); }
}
