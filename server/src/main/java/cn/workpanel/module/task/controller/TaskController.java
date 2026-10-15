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
    /** 分页查询范围内任务。支持 search、ownerId、date、period、cursor、limit；越权 ownerId 返回 403。 */
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit,@RequestParam(defaultValue="") String search,@RequestParam(required=false) String ownerId,@RequestParam(required=false) String date,@RequestParam(defaultValue="day") String period) {
        return queries.list(Actor.current(r),new cn.workpanel.module.task.TaskQueryService.Query(cursor,limit,search,ownerId,date,period));
    }
    /**
     * 追加任务生命周期事件。仅支持 RECEIVED、FEEDBACK、ACCEPTED、RETURNED、ARCHIVED、WITHDRAWN；
     * 请求必须有当前 version，反馈、退回、撤回必须有 1–2000 字 text。
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
    /** 提交已发布任务的通用修订。需 version 和 reason；负责人或截止时间变更返回 USE_DEDICATED_REVISION，须走专用复核接口。 */
    @PostMapping("/{id}/revisions") @Transactional
    public Map<String,Object> revision(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object> b) {
        Db.fields(b,"version","reason","candidate"); Actor a=Actor.current(r); a.requireDispatch(); var t=business.task(a,id,true); if(!a.id().equals(t.get("issuer_id"))&&!a.admin()) throw ApiError.forbidden(); if(Set.of("ARCHIVED","WITHDRAWN").contains(t.get("phase"))) throw ApiError.conflict();
        if(!(b.get("candidate") instanceof Map<?,?>)) throw ApiError.bad("INVALID_CANDIDATE","candidate 必须为对象"); var c=revisions.validateGeneric(db,a,t,db.read(db.write(b.get("candidate"))));
        return reviews.create(a,"TASK",id,Db.version(b),db.read(t.get("body")),c,Db.required(b,"reason"));
    }
}
