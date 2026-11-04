package cn.workpanel.module.task.controller;

import cn.workpanel.*;
import cn.workpanel.module.review.application.ReviewApplicationService;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/tasks")
/** 任务接口。列表隐藏完成情况字段，生命周期通过详情 events 表达。 */
public class TaskController {
    final cn.workpanel.module.task.application.TaskMovementApplication movements;
    final cn.workpanel.module.task.TaskPinService pins;
    final Business business; final Db db; final ReviewApplicationService reviews; final cn.workpanel.module.task.TaskLifecycleService lifecycle; final cn.workpanel.module.task.TaskRevisionService revisions; final cn.workpanel.module.task.TaskQueryService queries;
    public TaskController(Business business, Db db, ReviewApplicationService reviews, cn.workpanel.module.task.TaskLifecycleService lifecycle, cn.workpanel.module.task.TaskRevisionService revisions, cn.workpanel.module.task.TaskQueryService queries, cn.workpanel.module.task.application.TaskMovementApplication movements,cn.workpanel.module.task.TaskPinService pins) { this.pins=pins; this.movements=movements; this.business=business; this.db=db; this.reviews=reviews; this.lifecycle=lifecycle; this.revisions=revisions; this.queries=queries; }
    /** 分页查询范围内任务。支持 search、participantId、date、period、cursor、limit；越权参与人筛选返回 403。 */
    @io.swagger.v3.oas.annotations.Operation(summary="范围内任务列表",description="date/period 和 from/to 均按任务区间相交。新 from/to 为带时区 [from,to)，最多 62 日，COALESCE(start_at,deadline)<to AND deadline>=from。不得混用 date/period；ownerId 为 participantId 兼容别名，两者不同返回 400；参与人须经授权。范围响应含 snapshotToken、scheduleConstraints，后页须原 token；变化 409 CALENDAR_SNAPSHOT_CHANGED，超过 5000 条 422 CALENDAR_RANGE_TOO_DENSE；末页 nextCursor 为 null。列表 capabilities.reschedule 为当前部署及角色能力，不含业务状态列。")
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(defaultValue="") String search,@RequestParam(required=false) String participantId,@RequestParam(required=false) String date,@RequestParam(required=false) String period,
            @RequestParam(required=false) String from,@RequestParam(required=false) String to,@RequestParam(required=false) String snapshotToken,@RequestParam(required=false) String ownerId) {
        String canonical=text(participantId),alias=text(ownerId);
        if(canonical!=null&&alias!=null&&!canonical.equals(alias)) throw ApiError.bad("INVALID_PARTICIPANT_FILTER","ownerId 与 participantId 必须相同");
        return queries.list(Actor.current(r),new cn.workpanel.module.task.TaskQueryService.Query(cursor,limit,search,canonical!=null?canonical:alias,text(date),text(period),text(from),text(to),text(snapshotToken),null));
    }
    /** 旧内部调用签名保留；非 HTTP 路由，兼容既有分析导出适配。 */
    public Map<String,Object> list(HttpServletRequest r,int cursor,int limit,String search,String participantId,String date,String period) {
        return queries.list(Actor.current(r),new cn.workpanel.module.task.TaskQueryService.Query(cursor,limit,search,participantId,date,period));
    }

    /**
     * 个人置顶本人可见任务，只影响本人 GET /api/tasks 排序（置顶优先、最近置顶在前），不改变任务 version、不走审核、不通知他人。
     * 每人最多 10 项（仅计仍可见任务），超出 409 PIN_LIMIT；范围外任务 404；已置顶返回原 pinnedAt（幂等）。
     */
    @PutMapping("/{id}/pin") public Map<String,Object> pin(HttpServletRequest r,@PathVariable String id) { return pins.pin(Actor.current(r),id); }
    /** 取消本人置顶；未置顶也返回成功（幂等）。范围外任务 404，无版本要求。 */
    @DeleteMapping("/{id}/pin") public Map<String,Object> unpin(HttpServletRequest r,@PathVariable String id) { return pins.unpin(Actor.current(r),id); }

    /** 空白参数按未提供处理，避免 `ownerId=` 之类的空值被当成筛选值或区间端点。 */
    private static String text(String value) { return value==null||value.isBlank()?null:value.trim(); }
    /**
     * 当前 Actor 本人参与的任务卡片历史（含本人派发且参与）；返回 {items,total,nextCursor}，不按完成状态过滤，
     * 撤回、验收、归档记录均保留。每项含 id/title/start_at/deadline/version/phase/dispatchAt/participants/label/createdAt，
     * dispatchAt 为最早真实 DISPATCHED 事件时间，缺失为 null 并排在末尾，同时间按 id 稳定排序。
     * 支持 search（≤200 字）、cursor、limit（1–100）；范围外任务不返回；只读 GET 无版本和幂等键。
     */
    @GetMapping("/received-card") public Map<String,Object> receivedCard(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(defaultValue="") String search) {
        return queries.receivedCard(Actor.current(r),cursor,limit,search);
    }
    /**
     * 追加任务生命周期事件。仅支持 RECEIVED、FEEDBACK、ACCEPTED、RETURNED、ARCHIVED、WITHDRAWN；
     * 请求必须有当前 version，反馈、退回、撤回必须有 1–2000 字 text；FEEDBACK可带最多5个attachments，绑定/版本/事件/outbox同事务。
     * 转派、改期须使用专用复核申请接口；非法状态返回 INVALID_TRANSITION，版本过期返回 VERSION_CONFLICT。
     */
    @PostMapping("/{id}/events") @Transactional
    public Map<String,Object> event(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        return lifecycle.apply(Actor.current(r),id,b);
    }
    /**
     * 提交转派复核申请。仅派发人或管理员可申请；请求须含 ownerId、version、reason。
     * 复核通过前不改变负责人或状态；同一负责人返回 SAME_OWNER，终态返回 INVALID_TRANSITION。
     */
    @PostMapping("/{id}/reassignments") @Transactional
    public Map<String,Object> reassignment(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); var request=revisions.prepareReassignment(a,id,b);
        return reviews.create(a,"TASK_REASSIGN",id,request.version(),request.before(),request.candidate(),Db.required(b,"reason"));
    }
    /**
     * 提交改期复核申请。仅派发人或管理员可申请；请求须含带时区 deadline、version、reason。
     * 兼容 deadline 模式；MOVE 仅接受正 int32 version、非零 int32 moveDays、1–1000 码点 reason。
     * MOVE 必须携带 Idempotency-Key / If-Schedule-Constraints-Match；返回原审核申请，正式起止时间不变。
     * 403/404 遵循现有权限；409 区分版本、键内容、待审占用、约束变化与版本耗尽。
     */
    @io.swagger.v3.oas.annotations.Operation(summary="申请任务改期（兼容截止时间或整段移动）",description="旧模式：deadline/version/reason。MOVE 模式：version 为正 int32，moveDays 为非零 int32，reason 为去 Unicode 空白后 1–1000 码点；只允许这三个字段，必须给 Idempotency-Key（1–128 可见 ASCII，无空白）和 If-Schedule-Constraints-Match。返回审核申请；待审不改生效日期。同键相同内容返回原申请；同键不同内容、版本冲突、当前版本已待审、约束过期、版本耗尽返回 409。权限每次重检；关闭新模式仍可重放原申请。")
    @PostMapping("/{id}/reschedules") @Transactional
    public Map<String,Object> reschedule(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b,
            @RequestHeader(value="Idempotency-Key",required=false) String key,
            @RequestHeader(value="If-Schedule-Constraints-Match",required=false) String constraints) {
        return movements.request(Actor.current(r),id,b,key,constraints);
    }
    /** 提交已发布任务的通用修订。需 version 和 reason；参与人、标签和时间在审核通过后统一生效。 */
    @PostMapping("/{id}/revisions") @Transactional
    public Map<String,Object> revision(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"version","reason","candidate"); Actor a=Actor.current(r); a.requireDispatch(); var t=cn.workpanel.module.task.TaskAccess.readable(db,a,id,true); if(!a.id().equals(t.get("issuer_id"))&&!a.admin()) throw ApiError.forbidden(); if(Set.of("ARCHIVED","WITHDRAWN").contains(t.get("phase"))) throw ApiError.conflict();
        if(!(b.get("candidate") instanceof Map<?,?>)) throw ApiError.bad("INVALID_CANDIDATE","candidate 必须为对象"); var c=revisions.validateGeneric(db,a,t,db.read(db.write(b.get("candidate"))));
        return reviews.create(a,"TASK",id,Db.version(b),db.read(t.get("body")),c,Db.required(b,"reason"));
    }
    /** 提交删除审核申请；批准后仅归档并保留完整审计，不物理删除。 */
    @PostMapping("/{id}/deletions") @Transactional
    public Map<String,Object> deletion(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); var request=revisions.prepareDeletion(a,id,b);
        return reviews.create(a,"TASK_DELETE",id,request.version(),request.before(),request.candidate(),Db.required(b,"reason"));
    }
}
