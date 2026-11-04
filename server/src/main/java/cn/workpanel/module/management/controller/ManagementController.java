package cn.workpanel.module.management.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.management.application.ManagementApplicationService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

/** Web管理协议；所有接口仅ACTIVE ADMIN本公司范围，读取无版本且幂等，写入候选需version/reason且不自动重放。 */
@RestController
@RequestMapping("/api/management")
public class ManagementController {
    private final ManagementApplicationService service;
    public ManagementController(ManagementApplicationService service){this.service=service;}
    /** 管理账号分页，含停用账号；非法筛选400、越权403，响应items/total/nextCursor，无密码字段。 */
    @GetMapping("/accounts") public Map<String,Object> accounts(HttpServletRequest r,@RequestParam(defaultValue="")String search,@RequestParam(defaultValue="")String status,@RequestParam(defaultValue="")String departmentId,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="20")int limit){return service.accounts(Actor.current(r),search,status,departmentId,cursor,limit);}
    /** 本公司账号编辑信息及关联待审；跨公司/不存在404，无版本要求。 */
    @GetMapping("/accounts/{id}") public Map<String,Object> account(HttpServletRequest r,@PathVariable String id){return service.account(Actor.current(r),id);}
    /** 组织选择目录；仅本公司部门/团队和有效上级，无写入。 */
    @GetMapping("/options") public Map<String,Object> options(HttpServletRequest r){return service.options(Actor.current(r));}
    /** 提交账号候选，version/reason必填；无效400、待审归属/版本冲突409，审核前不生效。 */
    @PostMapping("/accounts/{id}/revisions") public Map<String,Object> accountRevision(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){return service.reviseAccount(Actor.current(r),id,b);}
    /** 公司事项管理分页，archived=false/true/all，含正式前十预览；非法400。 */
    @GetMapping("/items") public Map<String,Object> items(HttpServletRequest r,@RequestParam(defaultValue="")String search,@RequestParam(defaultValue="false")String archived,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="20")int limit){return service.items(Actor.current(r),search,archived,cursor,limit);}
    /** 本公司事项详情；跨公司/不存在404，响应正式值和version。 */
    @GetMapping("/items/{id}") public Map<String,Object> item(HttpServletRequest r,@PathVariable String id){return service.item(Actor.current(r),id);}
    /** 提交完整事项候选；新建version=0，更新需当前version/reason；非法400、冲突409。 */
    @PostMapping("/items/revisions") public Map<String,Object> itemRevision(HttpServletRequest r,@RequestBody Map<String,Object>b){return service.reviseItem(Actor.current(r),b);}
    /** 本人申请或分配审核分页，category=accounts/items；无效400，不扩大审核权限。 */
    @GetMapping("/reviews") public Map<String,Object> reviews(HttpServletRequest r,@RequestParam String category,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="20")int limit){return service.reviews(Actor.current(r),category,cursor,limit);}
    /** 三类管理申请前后值和审核步骤；未授权403/不存在404，只读。 */
    @GetMapping("/reviews/{id}") public Map<String,Object> review(HttpServletRequest r,@PathVariable String id){return service.review(Actor.current(r),id);}
    /** 当前独立复核人决定approve/reason；自审403，空驳回400，终态/业务版本冲突409，不幂等重放。 */
    @PostMapping("/reviews/{id}/decision") public Map<String,Object> decide(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){return service.decide(Actor.current(r),id,b);}
    /** 申请人无已处理步骤时重路由；无请求体/业务版本，越权403、状态冲突409。 */
    @PostMapping("/reviews/{id}/reroute") public Map<String,Object> reroute(HttpServletRequest r,@PathVariable String id){return service.reroute(Actor.current(r),id);}
}
