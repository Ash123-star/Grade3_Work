package cn.workpanel.module.attachment.controller;

import cn.workpanel.Actor;
import cn.workpanel.module.attachment.application.GeneratedFiles;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.nio.charset.StandardCharsets;

@RestController
@RequestMapping("/api/generated-files")
public class GeneratedFileController {
    private final GeneratedFiles files;
    public GeneratedFileController(GeneratedFiles files){this.files=files;}
    /** v1读取本人生成文件；当前ACTIVE身份、同公司及全部来源重新鉴权。id必需；成功二进制，404过期/不存在、403越权、409来源版本变化、503存储失败。只读无幂等键，不改变业务版本。 */
    @GetMapping("/{id}")public ResponseEntity<byte[]> download(HttpServletRequest request,@PathVariable String id){
        var file=files.download(Actor.current(request),id);
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).contentType(MediaType.APPLICATION_OCTET_STREAM).header("X-Content-Type-Options","nosniff").header(HttpHeaders.CONTENT_DISPOSITION,ContentDisposition.attachment().filename(file.filename(),StandardCharsets.UTF_8).build().toString()).body(file.bytes());
    }
}
