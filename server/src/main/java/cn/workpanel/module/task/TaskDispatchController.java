package cn.workpanel.module.task;

import cn.workpanel.Actor;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
@RequestMapping("/api/tasks")
public class TaskDispatchController {
    final TaskDispatchService service;
    public TaskDispatchController(TaskDispatchService service) { this.service=service; }

    /** 创建继续走既有幂等/审核；月历入口可携带约束头，过期 409、越界 400；无头旧客户端兼容。 */
    @PostMapping public Map<String,Object> dispatch(HttpServletRequest r,@RequestBody Map<String,Object> body,@RequestHeader(value="Idempotency-Key",required=false) String key,@RequestHeader(value="If-Schedule-Constraints-Match",required=false) String revision) {
        return service.dispatch(Actor.current(r),body,key,revision);
    }

    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) { return service.read(Actor.current(r),id); }
}
