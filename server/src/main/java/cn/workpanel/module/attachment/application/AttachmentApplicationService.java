package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.attachment.api.AttachmentApi;
import cn.workpanel.module.procedure.api.ProcedureAccess;
import cn.workpanel.shared.application.CurrentActors;
import cn.workpanel.shared.application.AiFilePolicy;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import java.security.MessageDigest;
import java.util.*;

/** 私有上传、正式用途绑定和受保护读取；管理角色不获得私人材料读取特权。 */
@Service
public class AttachmentApplicationService implements AttachmentApi {
    private final Db db;private final Business business;private final CurrentActors actors;private final ProcedureAccess procedures;
    public AttachmentApplicationService(Db db,Business business,CurrentActors actors,ProcedureAccess procedures){this.db=db;this.business=business;this.actors=actors;this.procedures=procedures;}
    @Transactional public Map<String,Object> upload(ActorContext context,Object source){
        return upload(context,source,"");
    }
    /** 可选AI用途仅收窄格式，不改变附件默认私有性；普通上传保持兼容。 */
    @Transactional public Map<String,Object> upload(ActorContext context,Object source,String purpose){
        Actor a=actors.fresh(context);
        if(!Set.of("","AI_WORK").contains(purpose))throw ApiError.bad("INVALID_PURPOSE","请选择有效的材料用途");
        if("AI_WORK".equals(purpose)&&source instanceof MultipartFile f)AiFilePolicy.size(f.getSize());
        if(!(source instanceof MultipartFile file)||file.isEmpty()||file.getSize()>10*1024*1024)throw ApiError.bad("INVALID_FILE","文件大小应在 1 字节至 10MB 之间");
        String name=Optional.ofNullable(file.getOriginalFilename()).orElse("attachment").replaceAll("[\\\\/\\r\\n]","_");if(name.length()>200)name=name.substring(name.length()-200);
        try{byte[] bytes=file.getBytes();String id=Db.id(),hash=hash(bytes);
            if("AI_WORK".equals(purpose))AiFilePolicy.validate(name,bytes);
            db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data,file_hash) VALUES (?,?,?,?,?,?,?)",id,a.company(),a.id(),name,"application/octet-stream",bytes,hash);
            return Map.of("id",id,"filename",name,"size",bytes.length,"hash",hash);
        }catch(java.io.IOException e){throw new ApiError(422,"FILE_UNREADABLE","文件暂时无法读取");}
    }
    public byte[] download(ActorContext a,String id){return (byte[])read(actors.fresh(a),id).get("data");}
    public Map<String,Object> read(Actor actor,String id){
        Actor a=actors.fresh(actor);var f=db.one("SELECT * FROM attachments WHERE company_id=? AND id=? AND octet_length(data)>0 AND (expires_at IS NULL OR expires_at>now())",a.company(),id);
        if(f.get("task_id")==null&&db.count("SELECT count(*) FROM attachment_bindings WHERE company_id=? AND attachment_id=? AND resource_type='WORK'",a.company(),id)>0
            &&db.count("SELECT count(*) FROM attachment_bindings b JOIN ai_work_items w ON w.company_id=b.company_id AND w.id=b.resource_id WHERE b.company_id=? AND b.attachment_id=? AND b.resource_type='WORK' AND w.deleted_at IS NULL",a.company(),id)==0
            &&db.count("SELECT count(*) FROM attachment_bindings WHERE company_id=? AND attachment_id=? AND resource_type IN ('PROCEDURE','DELIVERY')",a.company(),id)==0
            &&db.count("SELECT count(*) FROM users WHERE company_id=? AND profile->>'avatarAttachmentId'=?",a.company(),id)==0)throw new ApiError(404,"NOT_FOUND","内容不存在或已清除");
        boolean visible=a.id().equals(f.get("owner_id"));
        if(!visible){
            var owner=db.one("SELECT * FROM users WHERE id=? AND company_id=?",f.get("owner_id"),a.company());
            visible=(a.canSeeUser(owner)||Business.reportingAncestor(db,a,Db.str(owner,"id")))&&id.equals(Db.str(db.read(owner.get("profile")),"avatarAttachmentId"));
            if(!visible&&f.get("task_id")!=null){try{var t=business.task(a,Db.str(f,"task_id"),false);visible=Business.strings(db.read(t.get("body")),"attachments").contains(id);}catch(ApiError ignored){}}
            if(!visible)for(var binding:db.rows("SELECT resource_type,resource_id FROM attachment_bindings WHERE company_id=? AND attachment_id=?",a.company(),id)){
                try{
                    if("PROCEDURE".equals(binding.get("resource_type")))visible=Business.strings(procedures.get(a,Db.str(binding,"resource_id")),"attachmentIds").contains(id);
                    if("DELIVERY".equals(binding.get("resource_type"))){var delivery=db.one("SELECT task_id FROM task_deliveries WHERE company_id=? AND id=?",a.company(),binding.get("resource_id"));business.task(a,Db.str(delivery,"task_id"),false);visible=true;}
                }catch(ApiError ignored){}
                if(visible)break;
            }
        }
        if(!visible){if(f.get("task_id")!=null)business.task(a,Db.str(f,"task_id"),false);throw ApiError.forbidden();}return f;
    }
    public Map<String,Object> owned(Actor a,String id){var f=read(a,id);if(!a.id().equals(f.get("owner_id")))throw ApiError.forbidden();return f;}
    public List<Map<String,Object>> intake(Actor a,List<String> ids){
        if(ids.size()>AiFilePolicy.FILES)throw ApiError.bad("FILE_LIMIT","一次最多添加 5 份材料");long total=0;var files=new ArrayList<Map<String,Object>>();
        for(String id:ids){var f=owned(a,id);byte[] bytes=(byte[])f.get("data");AiFilePolicy.validate(Db.str(f,"filename"),bytes);total+=bytes.length;files.add(f);}
        if(total>AiFilePolicy.TOTAL_BYTES)throw ApiError.bad("FILE_LIMIT","材料总大小不能超过 30MB");return files;
    }
    public void bind(Actor a,String attachment,String type,String id){owned(a,attachment);db.update("INSERT INTO attachment_bindings(company_id,attachment_id,resource_type,resource_id) VALUES (?,?,?,?) ON CONFLICT DO NOTHING",a.company(),attachment,type,id);}
    public static String hash(byte[] bytes){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));}catch(Exception e){throw new IllegalStateException(e);}}
}
