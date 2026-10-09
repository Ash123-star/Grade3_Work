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
    final Db db; final Business business;
    public AttachmentController(Db db,Business business) { this.db=db; this.business=business; }
    /** 上传附件。需要登录；multipart 字段 file，大小 1 字节至 10MB；返回附件 id。 */
    @PostMapping(consumes="multipart/form-data") public Map<String,Object> upload(HttpServletRequest r,@RequestParam MultipartFile file) throws java.io.IOException {
        Actor a=Actor.current(r); if(file.isEmpty()||file.getSize()>10*1024*1024) throw ApiError.bad("INVALID_FILE","文件大小为 1 字节至 10MB"); String name=Optional.ofNullable(file.getOriginalFilename()).orElse("attachment").replaceAll("[\\\\/\\r\\n]","_"); if(name.length()>200) name=name.substring(name.length()-200); String id=Db.id();
        db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data) VALUES (?,?,?,?,?,?)",id,a.company(),a.id(),name,"application/octet-stream",file.getBytes()); return Map.of("id",id,"filename",name,"size",file.getSize());
    }
    /** 下载附件。所有者、头像授权范围或任务参与者可读；越权返回 403，响应禁止嗅探。 */
    @GetMapping("/{id}") public ResponseEntity<byte[]> download(HttpServletRequest r,@PathVariable String id) {
        Actor a=Actor.current(r); var f=db.one("SELECT * FROM attachments WHERE id=? AND company_id=?",id,a.company());
        if(!a.id().equals(f.get("owner_id"))) {
            var owner=db.one("SELECT * FROM users WHERE id=? AND company_id=?",f.get("owner_id"),a.company());
            boolean avatar=a.canSeeUser(owner)&&id.equals(Db.str(db.read(owner.get("profile")),"avatarAttachmentId"));
            if(!avatar) { if(f.get("task_id")==null) throw ApiError.forbidden(); business.task(a,Db.str(f,"task_id"),false); var t=db.one("SELECT body FROM tasks WHERE id=?",f.get("task_id")); if(!Business.strings(db.read(t.get("body")),"attachments").contains(id)) throw ApiError.forbidden(); }
        }
        return ResponseEntity.ok().contentType(MediaType.APPLICATION_OCTET_STREAM).header("X-Content-Type-Options","nosniff").header(HttpHeaders.CONTENT_DISPOSITION,ContentDisposition.attachment().filename(Db.str(f,"filename"),java.nio.charset.StandardCharsets.UTF_8).build().toString()).body((byte[])f.get("data"));
    }
}
