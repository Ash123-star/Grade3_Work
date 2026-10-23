package cn.workpanel.module.aiwork.controller;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.application.DeliveryService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/tasks/{taskId}")
public class DeliveryController {
    private final DeliveryService service;private final cn.workpanel.module.aiwork.application.DeliveryCheckJobs jobs;
    public DeliveryController(DeliveryService service,cn.workpanel.module.aiwork.application.DeliveryCheckJobs jobs){this.service=service;this.jobs=jobs;}
    /** 异步接收检查，202返回持久化检查ID；taskVersion/attachmentIds+幂等键，检查不改变任务，来源变化409。 */
    @PostMapping("/delivery-checks")@ResponseStatus(org.springframework.http.HttpStatus.ACCEPTED)public Map<String,Object> check(HttpServletRequest r,@PathVariable String taskId,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return jobs.create(Actor.current(r),taskId,b,key);}
    /** 恢复本人最近一次检查；任务范围外拒绝，不公开其他人的私人材料。 */
    @GetMapping("/delivery-checks")public Map<String,Object> latest(HttpServletRequest r,@PathVariable String taskId){return jobs.latest(Actor.current(r),taskId);}
    /** 本人检查报告，先重新验证任务读取权；不向其他可读上级公开私人材料。 */
    @GetMapping("/delivery-checks/{id}")public Map<String,Object> get(HttpServletRequest r,@PathVariable String taskId,@PathVariable String id){return jobs.get(Actor.current(r),taskId,id);}
    /** 创建正式交付及FEEDBACK，参数见DeliveryService；参与人、已接收阶段、task/check版本、文件清单同事务校验；幂等重放不重复反馈。 */
    @PostMapping("/deliveries")public Map<String,Object> submit(HttpServletRequest r,@PathVariable String taskId,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.submit(Actor.current(r),taskId,b,key);}
}
