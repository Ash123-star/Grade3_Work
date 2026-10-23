package cn.workpanel.module.comment;

import cn.workpanel.Actor;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 任务评论 HTTP 协议映射。 */
@RestController
@RequestMapping("/api/tasks/{taskId}/comments")
public class TaskCommentController {
    private final TaskCommentService comments;
    public TaskCommentController(TaskCommentService comments) { this.comments=comments; }
    @GetMapping public Map<String,Object> list(HttpServletRequest request,@PathVariable String taskId) { return Map.of("items",comments.list(Actor.current(request),taskId)); }
    @PostMapping public Map<String,Object> create(HttpServletRequest request,@PathVariable String taskId,@RequestBody Map<String,Object> body,@RequestHeader(value="Idempotency-Key",required=false) String key) { return comments.create(Actor.current(request),taskId,body,key); }
}
