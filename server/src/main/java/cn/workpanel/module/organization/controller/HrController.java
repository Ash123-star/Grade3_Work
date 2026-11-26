package cn.workpanel.module.organization.controller;
import cn.workpanel.*;import cn.workpanel.module.organization.application.*;import cn.workpanel.module.organization.domain.ContractDates;import jakarta.servlet.http.HttpServletRequest;import org.springframework.web.bind.annotation.*;import java.util.*;
/** 独立人事入口，认证后仍实时校验公司级READ/MANAGE；401未登录/403无权/404不存在/409版本冲突。 */
@RestController @RequestMapping("/api/hr") public class HrController {
 private final HrService service;private final ContractReminders reminders;private final HrAccess access;
 public HrController(HrService service,ContractReminders reminders,HrAccess access){this.service=service;this.reminders=reminders;this.access=access;}
 /** READ查询本人最新100条合同提醒，实时授权且只读幂等。 */
 @GetMapping("/reminders") @io.swagger.v3.oas.annotations.Operation(operationId="hr_reminders") public Object reminders(HttpServletRequest r){return service.reminders(Actor.current(r));}
 /** 查询本人能力，READ，幂等。 */
 @GetMapping("/me") @io.swagger.v3.oas.annotations.Operation(operationId="hr_me") public Object me(HttpServletRequest r){return service.me(Actor.current(r));}
 /** 最小员工目录，不含身份证/手机号；READ，幂等。 */
 @GetMapping("/employees") @io.swagger.v3.oas.annotations.Operation(operationId="hr_employees") public Object employees(HttpServletRequest r,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="100")int limit){return service.people(Actor.current(r),cursor,limit);}
 /** ADMIN授予NONE/READ/MANAGE，version必填，重复旧版本409。 */
 @PutMapping("/grants/{id}") @io.swagger.v3.oas.annotations.Operation(operationId="hr_grant") public Object grant(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){service.grant(Actor.current(r),id,b);return Map.of("ok",true);}
 /** MANAGE更新职责，duties/version必填；非法400、旧版本409。 */
 @PutMapping("/employees/{id}/duties") @io.swagger.v3.oas.annotations.Operation(operationId="hr_duties") public Object duties(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){service.duties(Actor.current(r),id,b);return Map.of("ok",true);}
 /** READ分页查询，cursor>=0/limit1..100，幂等，不含附件正文。 */
 @GetMapping("/contracts") @io.swagger.v3.oas.annotations.Operation(operationId="hr_list") public Object list(HttpServletRequest r,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="20")int limit){return service.list(Actor.current(r),cursor,limit);}
 /** READ合同详情及指定接收人；幂等，跨公司404。 */
 @GetMapping("/contracts/{id}") @io.swagger.v3.oas.annotations.Operation(operationId="hr_get") public Object get(HttpServletRequest r,@PathVariable String id){return service.get(Actor.current(r),id);}
 /** READ查询不可修改的合同历史版本；跨公司404，只读幂等。 */
 @GetMapping("/contracts/{id}/history") @io.swagger.v3.oas.annotations.Operation(operationId="hr_history") public Object history(HttpServletRequest r,@PathVariable String id){return service.history(Actor.current(r),id);}
 /** MANAGE归档；employeeId/title/startsOn/endsOn/attachmentId/recipients/version=0；专用附件唯一约束防重复。 */
 @PostMapping("/contracts") @io.swagger.v3.oas.annotations.Operation(operationId="hr_create") public Object create(HttpServletRequest r,@RequestBody Map<String,Object>b){return service.save(Actor.current(r),null,b);}
 /** MANAGE修订；字段同归档，version必填，附件不可替换，旧版本409。 */
 @PutMapping("/contracts/{id}") @io.swagger.v3.oas.annotations.Operation(operationId="hr_update") public Object update(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){return service.save(Actor.current(r),id,b);}
 /** ADMIN手动补扫当天节点，无日期参数；幂等去重。 */
 @PostMapping("/reminders/run") @io.swagger.v3.oas.annotations.Operation(operationId="hr_run") public Object run(HttpServletRequest r){Actor a=access.require(Actor.current(r),true);a.requireAdmin();return Map.of("queued",reminders.scan(ContractDates.today(),a.company()));}
}
