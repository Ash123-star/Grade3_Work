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

    @PostMapping public Map<String,Object> dispatch(HttpServletRequest r,@RequestBody Map<String,Object> body,@RequestHeader(value="Idempotency-Key",required=false) String key) {
        return service.dispatch(Actor.current(r),body,key);
    }

    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) { return service.read(Actor.current(r),id); }
}
