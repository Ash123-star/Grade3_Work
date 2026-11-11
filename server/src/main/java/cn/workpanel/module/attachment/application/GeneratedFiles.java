package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import java.util.*;

@Service
public class GeneratedFiles {
    private final Db db;private final BinaryFiles files;private final AttachmentApplicationService attachments;
    private final CurrentActors actors;private final GeneratedSourcePolicy policy;private final TransactionTemplate tx;private final int hours;
    public GeneratedFiles(Db db,BinaryFiles files,AttachmentApplicationService attachments,CurrentActors actors,GeneratedSourcePolicy policy,PlatformTransactionManager manager,@Value("${app.generated-file-hours:24}")int hours){
        this.db=db;this.files=files;this.attachments=attachments;this.actors=actors;this.policy=policy;this.hours=Math.max(1,Math.min(168,hours));
        tx=new TransactionTemplate(manager);tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }
    public record Result(String id,String filename,byte[] bytes){}
    public Result create(Actor actor,String kind,String filename,byte[] bytes,List<Map<String,Object>> sourceItems){
        Actor a=actors.fresh(actor);var sources=Map.<String,Object>of("items",sourceItems,"fingerprint",actors.fingerprint(a));policy.validate(a,sources);
        String id=Db.str(files.save(a,filename,bytes),"id");
        // 独立提交期限和来源；提交失败的未返回对象由孤儿清理处理。
        tx.executeWithoutResult(s->{db.update("INSERT INTO generated_files(id,company_id,owner_id,filename,kind,sources,attachment_id) VALUES (?,?,?,?,?,?::jsonb,?)",id,a.company(),a.id(),filename,kind,db.write(sources),id);db.update("UPDATE attachments SET expires_at=now()+(?*interval '1 hour') WHERE id=?",hours,id);});
        return download(a,id);
    }
    /** 下载重新读取当前身份并沿附件入口复核期限、来源权限和版本，生成时的授权不会永久生效。 */
    public Result download(Actor actor,String id){
        Actor a=actors.fresh(actor);var row=db.one("SELECT * FROM generated_files WHERE company_id=? AND id=? AND owner_id=?",a.company(),id,a.id());
        var file=attachments.read(a,Db.str(row,"attachment_id"));return new Result(id,Db.str(row,"filename"),(byte[])file.get("data"));
    }
}
