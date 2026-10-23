package cn.workpanel.module.procedure.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.procedure.application.ProcedureService;
import cn.workpanel.module.procedure.application.ProcedureTemplates;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

/** 公司正式资料 v1：同公司且范围内成员只读有效版本；维护与发布申请需管理员，最终发布独立审核。 */
@RestController @RequestMapping("/api/procedures")
public class ProcedureController {
    private final ProcedureService service;private final ProcedureTemplates templates;
    public ProcedureController(ProcedureService service,ProcedureTemplates templates){this.service=service;this.templates=templates;}
    /** v1查询有效资料或管理员草稿，search最长200，cursor>=0/limit1..100；受权检索后排序分页，返回items/total/nextCursor；只读无幂等要求，无权限403。 */
    @GetMapping public Map<String,Object> list(HttpServletRequest r,@RequestParam(defaultValue="")String search,@RequestParam(defaultValue="false")boolean drafts,@RequestParam(defaultValue="0")int cursor,@RequestParam(defaultValue="30")int limit){return service.list(Actor.current(r),search,drafts,cursor,limit);}
    /** 当前有效资料详情或管理员草稿，范围外404；不把草稿公开。 */
    @GetMapping("/{id}") public Map<String,Object> get(HttpServletRequest r,@PathVariable String id,@RequestParam(defaultValue="false")boolean draft){return service.get(Actor.current(r),id,draft);}
    /** 管理员比较当前正式版与维护稿；仅本人公司，未发布时published为空，不修改版本。 */
    @GetMapping("/{id}/comparison")public Map<String,Object> compare(HttpServletRequest r,@PathVariable String id){return service.compare(Actor.current(r),id);}
    /** 安全预填：version/reason；姓名/部门/日期只能由服务端身份生成，未知占位保持未填写；不提交审批或创建业务，模板失效/版本变化404/409。 */
    @PostMapping("/{id}/template-draft")public Map<String,Object> template(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b){return service.prepareTemplate(Actor.current(r),id,b);}
    /** v1即时预填并下载已发布模板的DOCX/XLSX附件；version/reason，姓名/部门/日期仅来自当前身份，未知占位/公式保留。每次按资料范围和附件绑定鉴权，过期/撤回404、版本变化409、不支持400；只读无副作用，无需幂等键。 */
    @PostMapping("/{id}/template-files/{file}")public org.springframework.http.ResponseEntity<byte[]> templateFile(HttpServletRequest r,@PathVariable String id,@PathVariable String file,@RequestBody Map<String,Object>b){
        var result=templates.prepare(Actor.current(r),id,file,b);
        return org.springframework.http.ResponseEntity.ok().header("Cache-Control","no-store").header("Content-Disposition",org.springframework.http.ContentDisposition.attachment().filename(result.filename(),java.nio.charset.StandardCharsets.UTF_8).build().toString()).contentType(org.springframework.http.MediaType.APPLICATION_OCTET_STREAM).body(result.bytes());
    }
    /** 新建资料草稿：title/type/content与适用范围；幂等键必需，同键异内容409，无效字段400；不会发布。 */
    @PostMapping public Map<String,Object> create(HttpServletRequest r,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.create(Actor.current(r),b,key);}
    /** 保存新版本：version/candidate；过期409，幂等键必需；旧正式版本继续有效。 */
    @PostMapping("/{id}/revisions") public Map<String,Object> revise(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.revise(Actor.current(r),id,b,key);}
    /** 申请发布/撤回：version/reason/withdraw；幂等键必需，最终独立审核，缺复核人保持待审。 */
    @PostMapping("/{id}/publish-requests") public Map<String,Object> publish(HttpServletRequest r,@PathVariable String id,@RequestBody Map<String,Object>b,@RequestHeader("Idempotency-Key")String key){return service.publish(Actor.current(r),id,b,key);}
}
