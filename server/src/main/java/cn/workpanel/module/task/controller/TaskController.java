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
    final Business business; final Db db; final ReviewApplicationService reviews; final cn.workpanel.module.task.TaskLifecycleService lifecycle; final cn.workpanel.module.task.TaskRevisionService revisions; final cn.workpanel.module.task.TaskQueryService queries;
    public TaskController(Business business, Db db, ReviewApplicationService reviews, cn.workpanel.module.task.TaskLifecycleService lifecycle, cn.workpanel.module.task.TaskRevisionService revisions, cn.workpanel.module.task.TaskQueryService queries) { this.business=business; this.db=db; this.reviews=reviews; this.lifecycle=lifecycle; this.revisions=revisions; this.queries=queries; }
    /**
     * 分页查询范围内任务。支持 date/period 或带时区 from/to、search、participantId（ownerId 为兼容别名）、cursor/limit。
     * from/to 必须成对出现、带时区且 to 晚于 from，不能与 date/period 混用；查询区间左闭右开，
     * 与任务区间 [start_at, deadline] 相交即命中。两个参与人别名同时出现且不同返回 400，
     * 越权参与人返回 403/404，非法区间返回 400。只读 GET 无版本要求、无幂等键。
     */
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(defaultValue="") String search,@RequestParam(required=false) String participantId,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(required=false) String period,@RequestParam(required=false) String from,@RequestParam(required=false) String to) {
        String canonical=text(participantId),alias=text(ownerId);
        if(canonical!=null&&alias!=null&&!canonical.equals(alias)) throw ApiError.bad("INVALID_PARTICIPANT_FILTER","ownerId 与 participantId 必须相同");
        String participant=canonical!=null?canonical:alias;
        return queries.list(Actor.current(r),new cn.workpanel.module.task.TaskQueryService.Query(cursor,limit,search,participant,date,period,text(from),text(to)));
    }

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
     * 复核通过前截止时间与状态均保持不变；同一截止时间返回 INVALID_DEADLINE。
     */
    @PostMapping("/{id}/reschedules") @Transactional
    public Map<String,Object> reschedule(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Actor a=Actor.current(r); var request=revisions.prepareReschedule(a,id,b);
        return reviews.create(a,"TASK_RESCHEDULE",id,request.version(),request.before(),request.candidate(),Db.required(b,"reason"));
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
