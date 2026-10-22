package cn.workpanel.module.aiwork.controller;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.application.WorkService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.HttpStatus;
import java.util.*;

/** AI办事 v1。全部事项本人私有；写命令需要 Idempotency-Key，版本冲突409、越权403/404、不可用503。 */
@RestController
@RequestMapping("/api/ai")
public class WorkController {
    private final WorkService service;private final cn.workpanel.module.aiwork.application.WorkEvents events;
    public WorkController(WorkService service,cn.workpanel.module.aiwork.application.WorkEvents events){this.service=service;this.events=events;}
    /** v1 本人事项 SSE，只传 change(id=持久序号,version)，GET 恢复正文。Last-Event-ID 为非负十进制且不得超前，非法400；最多3流/用户，超限429。refresh无id表示权限/来源视图变化；access-lost仅含401/403/404并终止，客户端须清缓存。Bearer仅放请求头，GET重连无副作用、无需幂等键。 */
    @GetMapping(value="/work-items/{id}/stream",produces="text/event-stream")public org.springframework.web.servlet.mvc.method.annotation.SseEmitter stream(HttpServletRequest r,@PathVariable String id,@RequestHeader(value="Last-Event-ID",defaultValue="0")String cursor){return events.open(Actor.current(r),id,cursor,r.getHeader("Authorization"));}
    /** 返回当前权限、真实服务能力和上传限制，不返回配置凭据。 */
    @GetMapping("/work-capabilities")public Map<String,Object> capabilities(HttpServletRequest r){return service.capabilities(Actor.current(r));}
    /** 本人事项分页，cursor>=0、limit1..100；返回业务摘要，接收成功不表示业务已执行。 */
    @GetMapping("/work-items")public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="30")int limit){return service.list(Actor.current(r),cursor,limit);}
    /** 新建私有事项；文字或1..5材料，可指定taskId/taskVersion；202返回持久化事项。 */
    @PostMapping("/work-items")@ResponseStatus(HttpStatus.ACCEPTED)public Map<String,Object> create(HttpServletRequest r,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.create(Actor.current(r),b,key);}
    /** 按实时本人和来源权限读取消息、进度、结果及一次确认凭据。 */
    @GetMapping("/work-items/{id}")public Map<String,Object> get(HttpServletRequest r,@PathVariable String id){return service.get(Actor.current(r),id);}
    /** 追加不可变消息，需要version，重新规划未完成动作；同键异内容409。 */
    @PostMapping("/work-items/{id}/messages")public Map<String,Object> message(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.message(Actor.current(r),id,b,key);}
    /** 确认本次具体动作；version/planVersion/planHash/confirmationId/actions必须匹配10分钟内计划。 */
    @PostMapping("/work-items/{id}/confirm")public Map<String,Object> confirm(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.confirm(Actor.current(r),id,b,key);}
    /** version+幂等键停止后续办理；保留已提交业务。 */
    @PostMapping("/work-items/{id}/cancel")public Map<String,Object> cancel(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.command(Actor.current(r),id,"cancel",b,key);}
    /** version+幂等键仅续办失败步骤，不重复已成功动作。 */
    @PostMapping("/work-items/{id}/retry")public Map<String,Object> retry(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.command(Actor.current(r),id,"retry",b,key);}
    /** If-Match为正整数事项版本；立即停止新动作并隐藏私人内容，不删除正式交付。 */
    @DeleteMapping("/work-items/{id}")@ResponseStatus(HttpStatus.ACCEPTED)public Map<String,Object> delete(HttpServletRequest r,@PathVariable String id,@RequestHeader("If-Match")int version,@RequestHeader("Idempotency-Key")String key){return service.command(Actor.current(r),id,"delete",Map.of("version",version),key);}
    /** 当前本人限定授权列表，默认无授权。 */
    @GetMapping("/work-authorizations")public List<Map<String,Object>> authorizations(HttpServletRequest r){return service.authorizations(Actor.current(r));}
    /** v1只读当前公司的自动授权上限与本人可用动作；所有已确认成员可读，无幂等要求。修改须管理员通过organization/review-policy/revisions独立复核。 */
    @GetMapping("/work-authorization-policy")public Map<String,Object> authorizationPolicy(HttpServletRequest r){return service.authorizationPolicy(Actor.current(r));}
    /** 授权对象选择：action白名单、search最长200、cursor非负；实时权限过滤，只返回姓名/标题和组织名称，不暴露任务状态。 */
    @GetMapping("/work-authorization-options")public Map<String,Object> options(HttpServletRequest r,@RequestParam String action,@RequestParam(defaultValue="")String search,@RequestParam(defaultValue="0")int cursor){return service.authorizationOptions(Actor.current(r),action,search,cursor);}
    /** action/scope(ownerIds或taskIds/maxActions)/带时区expiresAt，须满足公司允许动作、期限/对象/每批上限，最长30天；Idempotency-Key必需，同键异内容409、公司限制400，不能授权本人没有的业务权限。 */
    @PostMapping("/work-authorizations")public Map<String,Object> authorize(HttpServletRequest r,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.authorize(Actor.current(r),b,key);}
    /** 版本+幂等键撤回限定授权；与正在提交的动作按用户锁串行。 */
    @PostMapping("/work-authorizations/{id}/revoke")public Map<String,Object> revoke(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.revoke(Actor.current(r),id,b,key);}
}
