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
    /** 当前任务可读者读取只追加评论；返回items，含父ID/作者昵称/头像/正文/时间。无版本、幂等键或分页参数；不可见404。 */
    @GetMapping public Map<String,Object> list(HttpServletRequest request,@PathVariable String taskId) { return Map.of("items",comments.list(Actor.current(request),taskId)); }
    /** 参与人、派发人或管理员追加评论/回复：text 1–2000字，parentId须同任务，Idempotency-Key 1–128位必填；重复409 DUPLICATE_COMMENT，无效400、越权403/404。无版本，评论审计/outbox同事务，不支持改删。 */
    @PostMapping public Map<String,Object> create(HttpServletRequest request,@PathVariable String taskId,@RequestBody Map<String,Object> body,@RequestHeader(value="Idempotency-Key",required=false) String key) { return comments.create(Actor.current(request),taskId,body,key); }
}
