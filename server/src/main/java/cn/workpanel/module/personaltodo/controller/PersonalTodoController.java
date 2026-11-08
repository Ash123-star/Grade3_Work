package cn.workpanel.module.personaltodo.controller;

import cn.workpanel.*;
import cn.workpanel.module.personaltodo.api.TodoContracts.*;
import cn.workpanel.module.personaltodo.application.PersonalTodoService;
import cn.workpanel.module.personaltodo.domain.TodoDraft;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** v1 private todos. Active authenticated owner only; no organization traversal or task linkage.
 * Dates are Shanghai civil dates; errors use code/message/traceId. Unknown parameters are rejected.
 * Mutations require Idempotency-Key (24h replay); updates/deletes also require a positive version.
 * 400 invalid input, 401 unauthenticated, 403 pending, 404 missing/other owner, 409 conflict, 429 throttled.
 */
@RestController
@RequestMapping("/api/personal-todos")
public class PersonalTodoController {
    private final PersonalTodoService service;
    public PersonalTodoController(PersonalTodoService service) { this.service=service; }
    private static void query(HttpServletRequest r,String... names) {
        var allowed=Set.of(names);
        r.getParameterMap().forEach((name,values)->{if(!allowed.contains(name)||values.length!=1) throw ApiError.bad("UNKNOWN_FIELD","未知或重复查询参数");});
    }
    /** Read only owner's day; cursor offset, limit 1–100, terminal nextCursor=null. No idempotency/version needed. */
    @Operation(operationId="listPersonalTodos",summary="分页读取本人每日事项",description="仅本人；date为自然日，返回与该日重叠的事项（跨天事项在覆盖的每一天都返回）；cursor>=0，limit 1–100；末页nextCursor=null；拒绝ownerId代查。")
    @GetMapping public Page list(HttpServletRequest r,@RequestParam String date,@RequestParam(defaultValue="0") int cursor,@RequestParam(defaultValue="30") int limit) {
        query(r,"date","cursor","limit");return service.list(Actor.current(r),date,cursor,limit);
    }
    /** Read-only bounded month grid counts, inclusive fromDate/exclusive toDate, including adjacent weeks. */
    @Operation(operationId="personalTodoCalendar",summary="读取本人事项月历计数",description="month为YYYY-MM，周一开始的完整网格，仅本人；无版本或幂等要求。")
    @GetMapping("/calendar") public cn.workpanel.module.personaltodo.api.TodoContracts.Calendar calendar(HttpServletRequest r,@RequestParam String month) {
        query(r,"month");return service.calendar(Actor.current(r),month);
    }
    /** Read owner's current record; other owner/deleted/missing all 404. No idempotency/version needed. */
    @Operation(operationId="personalTodoDetail",summary="读取本人事项详情",description="其他用户、已删除或不存在统一404；不允许管理员代查。")
    @GetMapping("/{id}") public Todo detail(HttpServletRequest r,@PathVariable String id) {
        query(r);return service.detail(Actor.current(r),id);
    }
    /** Create owner-bound todo, version=1/completed=false; replay returns same 201 entity for 24 hours. */
    @Operation(operationId="createPersonalTodo",summary="新增本人事项",description="title 1–120字，note最多2000字，date有效1900–2100自然日；endDate不早于date且跨度≤366天，默认等于date；color为#RRGGBB，默认#F3A45D；必须提供Idempotency-Key，未知字段400，同键异参409。")
    @PostMapping @ResponseStatus(HttpStatus.CREATED)
    public Todo create(HttpServletRequest r,@RequestHeader(value="Idempotency-Key") String key,
        @io.swagger.v3.oas.annotations.parameters.RequestBody(content=@Content(schema=@Schema(implementation=Create.class))) @RequestBody Map<String,Object> body) {
        query(r);return service.create(Actor.current(r),TodoDraft.parse(body,false),key);
    }
    /** Replace editable fields by expected version; target completed value is idempotent, never toggled on replay. */
    @Operation(operationId="updatePersonalTodo",summary="编辑或完成本人事项",description="全量title/note/date/endDate/color/completed/version；endDate不早于date且跨度≤366天；正整数version，必须提供Idempotency-Key。旧版本或同键异参409；同键同请求返回原结果。")
    @PutMapping("/{id}") public Todo update(HttpServletRequest r,@PathVariable String id,@RequestHeader(value="Idempotency-Key") String key,
        @io.swagger.v3.oas.annotations.parameters.RequestBody(content=@Content(schema=@Schema(implementation=Update.class))) @RequestBody Map<String,Object> body) {
        query(r);return service.update(Actor.current(r),id,TodoDraft.parse(body,true),key);
    }
    /** Version-checked logical deletion. Returns receipt; same key replay succeeds even after deletion. */
    @Operation(operationId="deletePersonalTodo",summary="删除本人事项",description="version为正整数，必须提供Idempotency-Key；成功返回id/deleted/version；同键同请求24小时内重放，旧版本409，越权404。")
    @DeleteMapping("/{id}") public Deleted delete(HttpServletRequest r,@PathVariable String id,@RequestParam int version,@RequestHeader(value="Idempotency-Key") String key) {
        query(r,"version");return service.delete(Actor.current(r),id,version,key);
    }
}
