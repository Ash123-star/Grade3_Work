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
    /**
     * 分页查询本人或授权范围内已提交日报。参数 ownerId、cursor、limit，日期条件为date/period
     * 或成对带时区的上海自然日 from/to（左闭右开），两者互斥；period 缺省为 day。
     * 越权 ownerId 返回 403，区间/搜索非法返回 400；只读，无幂等键。
     */
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(required=false) String period,@RequestParam(required=false) String from,@RequestParam(required=false) String to) {
        return queries.list(Actor.current(r),new LogQueryService.Query(cursor,limit,ownerId,date,period,null,null,from,to),false);
    }
    /**
     * 管理者下属日志：ownerId、departmentId、search 与date/period 或成对上海零点 from/to 组合过滤，
     * 只返回当前组织范围或实时直属关系内在职成员的已提交正文。from/to 必须成对且与 date/period 互斥（400）；
     * 非管理者、越权或调岗失权 403；cursor/limit 分页；只读，无幂等键。
     */
    @GetMapping("/subordinates") public Map<String,Object> subordinates(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(required=false) String period,@RequestParam(required=false) String departmentId,@RequestParam(required=false) String search,@RequestParam(required=false) String from,@RequestParam(required=false) String to) {
        return queries.list(Actor.current(r),new LogQueryService.Query(cursor,limit,ownerId,date,period,departmentId,search,from,to),true);
    }
    /**
     * 读取授权成员上海自然月每日提交状态。参数 ownerId 与 month=YYYY-MM；返回 ownerId/month/
     * employmentStartDate（可空）/days，days 覆盖该月每个自然日，状态为 SUBMITTED、MISSING、FUTURE 或 UNKNOWN。
     * 本人、非管理者、越权、失权或非在职成员 403；月份格式错误 400；只读且不分页、不要求幂等键。
     */
    @GetMapping("/subordinates/calendar") public Map<String,Object> subordinateCalendar(HttpServletRequest r,@RequestParam String ownerId,@RequestParam String month) {
        return queries.calendar(Actor.current(r),ownerId,month);
    }
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
    /**
     * 本人首次提交后24小时内直接更新 work 正文。请求 {work,version}；保存历史版本并使旧待审 LOG 候选失效。
     * 版本冲突、超时和非已提交日志均返回可区分的409；非作者403；保留首次 submitted_at。
     */
    @PutMapping("/{id}/content") @Transactional
    public Map<String,Object> updateContent(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        return workflow.updateContent(Actor.current(r),id,b);
    }
    /** 获取日报历史版本。本人或授权范围内上级可读；返回按版本升序的历史内容。 */
    @GetMapping("/{id}/versions") public List<Map<String,Object>> versions(HttpServletRequest r,@PathVariable String id) { return workflow.versions(Actor.current(r),id); }
    /** 获取日报评语。需要日志可见权限；返回评语作者和时间。 */
    @GetMapping("/{id}/comments") public List<Map<String,Object>> comments(HttpServletRequest r,@PathVariable String id) { return workflow.comments(Actor.current(r),id); }
    /** 追加公开评论或回复：已有日志读取权限，text为1至2000字，可选parentId必须属于同日志。返回id/actor_id/author_name/text/parent_id/created_at；无版本或幂等键，重复POST产生新评论。无效400、草稿403、不可见404；不支持改删，不受24小时正文窗口限制。 */
    @PostMapping("/{id}/comments") @Transactional public Map<String,Object> comment(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) { return workflow.comment(Actor.current(r),id,b); }
}
