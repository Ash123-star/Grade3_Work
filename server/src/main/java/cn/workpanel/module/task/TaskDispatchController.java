package cn.workpanel.module.task;

import cn.workpanel.Actor;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/tasks")
public class TaskDispatchController {
    final TaskDispatchService service;
    @org.springframework.beans.factory.annotation.Value("${workpanel.task.proposals-enabled:false}") boolean proposalsEnabled;
    public TaskDispatchController(TaskDispatchService service) { this.service=service; }

    /** v1：提交任务候选，返回审批申请（不是已派发任务）。旧客户端须有派发资格；启用开关后在职成员可用
     * Task-Dispatch-Policy: recipient-confirmation-v1 走上级批准和必要的本人确认。Idempotency-Key 同键同策略同内容重放；
     * 异内容或策略不一致409，非法草稿400，跨公司人员404，不具权限403。月历约束头过期409、越界400。 */
    @PostMapping public Map<String,Object> dispatch(HttpServletRequest r,@RequestBody Map<String,Object> body,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestHeader(value="If-Schedule-Constraints-Match",required=false) String revision,
            @RequestHeader(value="Task-Dispatch-Policy",required=false) String policy) {
        if(policy==null) return service.dispatch(Actor.current(r),body,key,revision);
        if(!"recipient-confirmation-v1".equals(policy)||!proposalsEnabled) throw new cn.workpanel.ApiError(409,"DISPATCH_POLICY_UNAVAILABLE","当前环境尚未启用此派发策略");
        return service.submit(Actor.current(r),body,key,revision,true);
    }

    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) { return service.read(Actor.current(r),id); }
}
