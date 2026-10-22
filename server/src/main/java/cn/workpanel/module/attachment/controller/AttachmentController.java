package cn.workpanel.module.attachment.controller;

import cn.workpanel.*;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.util.*;

@RestController
@RequestMapping("/api/attachments")
/** 附件接口。文件存储在后端受控存储中，下载始终重新执行对象授权。 */
public class AttachmentController {
    final cn.workpanel.module.attachment.application.AttachmentApplicationService service;
    public AttachmentController(cn.workpanel.module.attachment.application.AttachmentApplicationService service) { this.service=service; }
    /** 上传私有附件。v1登录接口；file为1字节至10MB，purpose可省略或AI_WORK。
     * AI用途校验签名/扩展名，400超限或用途无效、415不支持/伪装格式；深度解析错误在检查结果返回。
     * 上传每次产生新ID，不改变业务对象、不承诺请求幂等；后续办事命令使用幂等键。
     */
    @PostMapping(consumes="multipart/form-data") public Map<String,Object> upload(HttpServletRequest r,@RequestParam MultipartFile file,@RequestParam(defaultValue="") String purpose) throws java.io.IOException {
        return service.upload(cn.workpanel.module.review.api.ReviewActors.context(Actor.current(r)),file,purpose);
    }
    /** 下载附件。所有者、头像授权范围或任务参与者可读；越权返回 403，响应禁止嗅探。 */
    @GetMapping("/{id}") public ResponseEntity<byte[]> download(HttpServletRequest r,@PathVariable String id) {
        var f=service.read(Actor.current(r),id);
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_OCTET_STREAM).header("X-Content-Type-Options","nosniff").header(HttpHeaders.CONTENT_DISPOSITION,ContentDisposition.attachment().filename(Db.str(f,"filename"),java.nio.charset.StandardCharsets.UTF_8).build().toString()).body((byte[])f.get("data"));
    }
}
