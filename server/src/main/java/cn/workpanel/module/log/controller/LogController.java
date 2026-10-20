package cn.workpanel.module.log.controller;

import cn.workpanel.*;
import cn.workpanel.module.log.application.LogQueryService;
import cn.workpanel.module.log.application.LogWorkflowService;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/logs")
/** 日报接口。草稿仅本人可见，管理范围查询只返回已提交版本。 */
public class LogController {
    final LogWorkflowService workflow; final LogQueryService queries;
    public LogController(LogWorkflowService workflow,LogQueryService queries) { this.workflow=workflow; this.queries=queries; }
    /** 分页查询本人或授权范围内已提交日报。支持 ownerId、date、period、cursor、limit。 */
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period) {
        return queries.list(Actor.current(r),new LogQueryService.Query(cursor,limit,ownerId,date,period),false);
    }
    /** 管理者下属日志：departmentId/date/period/search 可组合；groups 分组当前日志页，保留 items/total/nextCursor。员工403，未知和越权部门均空结果；关键词超过100字400。只读，无幂等键。 */
    @GetMapping("/subordinates") public Map<String,Object> subordinates(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period,@RequestParam(required=false) String departmentId,@RequestParam(required=false) String search) { return queries.list(Actor.current(r),new LogQueryService.Query(cursor,limit,ownerId,date,period,departmentId,search),true); }
    /** 兼容统计与导出模块的内部调用；范围和草稿私密性仍由查询服务统一执行。 */
    public Map<String,Object> list(Actor actor,int cursor,int limit,String ownerId,String date,String period,boolean subordinate) {
        return queries.list(actor,new LogQueryService.Query(cursor,limit,ownerId,date,period),subordinate);
    }
    /** 获取日报详情；草稿仅本人可读，上级读取不到未提交内容。 */
    @GetMapping("/{id}") public Map<String,Object> detail(HttpServletRequest r,@PathVariable String id) { return workflow.detail(Actor.current(r),id); }
    /** 保存本人某业务日期的日报草稿。请求含 businessDate 和 body；同一用户同一天幂等覆盖。 */
    @PutMapping("/draft") @Transactional
    public Map<String,Object> draft(HttpServletRequest r,@RequestBody Map<String,Object> b) {
        return workflow.saveDraft(Actor.current(r),b);
    }
    /** 提交日报。需当前 version；提交后上级可见，版本冲突返回 409。 */
    @PostMapping("/{id}/submit") @Transactional
    public Map<String,Object> submit(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        return workflow.submit(Actor.current(r),id,b);
    }
    /** 提交已发布日报修订。需 version、reason；按审核链生效。 */
    @PostMapping("/{id}/revisions") @Transactional
    public Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        return workflow.revise(Actor.current(r),id,b);
    }
    /** 获取日报历史版本。本人或授权范围内上级可读；返回按版本升序的历史内容。 */
    @GetMapping("/{id}/versions") public List<Map<String,Object>> versions(HttpServletRequest r,@PathVariable String id) { return workflow.versions(Actor.current(r),id); }
    /** 本人窗口内撤回；version/reason 必填，超时409、越权403；版本控制重复请求，成功返回当前日志能力字段。 */
    @PostMapping("/{id}/withdraw") @Transactional
    public Map<String,Object> withdraw(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { return workflow.withdraw(Actor.current(r),id,b); }
    /** 标记已提交日报为已读。需要日志可见权限；草稿不能标记。 */
    @PostMapping("/{id}/read") public Map<String,Object> read(HttpServletRequest r,@PathVariable String id) { return workflow.markRead(Actor.current(r),id); }
    /** 获取日报评语。需要日志可见权限；返回评语作者和时间。 */
    @GetMapping("/{id}/comments") public List<Map<String,Object>> comments(HttpServletRequest r,@PathVariable String id) { return workflow.comments(Actor.current(r),id); }
    /** 追加公开评论或回复：已有日志读取权限，text为1至2000字，可选parentId必须属于同日志。返回id/actor_id/author_name/text/parent_id/created_at；无版本或幂等键，重复POST产生新评论。无效400、草稿403、不可见404；不支持改删，不受24小时正文窗口限制。 */
    @PostMapping("/{id}/comments") @Transactional public Map<String,Object> comment(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { return workflow.comment(Actor.current(r),id,b); }
}
