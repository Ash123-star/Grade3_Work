package cn.workpanel.module.task.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.task.TaskLabelService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** 标签查询及创始人维护接口。 */
@RestController
@RequestMapping("/api/task-labels")
public class TaskLabelController {
    private final TaskLabelService labels;
    public TaskLabelController(TaskLabelService labels) { this.labels=labels; }
    @GetMapping public Map<String,Object> list(HttpServletRequest request) { return Map.of("items",labels.list(Actor.current(request))); }
    @PostMapping public Map<String,Object> create(HttpServletRequest request,@RequestBody Map<String,Object> body) { return labels.create(Actor.current(request),body); }
    @PutMapping("/{id}") public Map<String,Object> update(HttpServletRequest request,@PathVariable String id,@RequestBody Map<String,Object> body) { return labels.update(Actor.current(request),id,body); }
}
