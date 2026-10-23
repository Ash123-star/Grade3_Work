package cn.workpanel.module.procedure.application;

import cn.workpanel.*;
import cn.workpanel.module.procedure.api.ProcedureAccess;
import cn.workpanel.module.attachment.application.AttachmentApplicationService;
import cn.workpanel.module.aiwork.infrastructure.ParserProcess;
import cn.workpanel.shared.application.*;
import org.springframework.stereotype.Service;
import java.util.*;

/** 预填产物即时返回，不建立公开地址或共享原始私有材料。 */
@Service
public class ProcedureTemplates {
    private final ProcedureService procedures;private final ProcedureAccess access;private final AttachmentApplicationService attachments;private final ParserProcess parser;private final CurrentActors actors;
    public ProcedureTemplates(ProcedureService procedures,ProcedureAccess access,AttachmentApplicationService attachments,ParserProcess parser,CurrentActors actors){this.procedures=procedures;this.access=access;this.attachments=attachments;this.parser=parser;this.actors=actors;}
    public record Prepared(String filename,byte[] bytes){}
    public Prepared prepare(Actor actor,String id,String file,Map<String,Object> body){
        Actor a=actors.fresh(actor);var source=procedures.prepareTemplate(a,id,body);
        if(!Business.strings(source,"attachmentIds").contains(file))throw ApiError.notFound();var attachment=attachments.read(a,file);String filename=Db.str(attachment,"filename");
        String type=AiFilePolicy.validate(filename,(byte[])attachment.get("data"));if(!Set.of("DOCX","XLSX").contains(type))throw ApiError.bad("INVALID_TEMPLATE","这份材料不支持预填，请下载原件");
        byte[] result=parser.renderTemplate((byte[])attachment.get("data"),procedures.templateFields(a,body));
        // 解析期间发布/撤回、调岗、停用时不再交付旧来源产物。
        Actor current=actors.fresh(a);if(!actors.fingerprint(a).equals(actors.fingerprint(current)))throw ApiError.forbidden();
        var latest=access.get(current,id);if(!Objects.equals(latest.get("version"),source.get("version"))||!Business.strings(latest,"attachmentIds").contains(file))throw new ApiError(409,"SOURCE_CHANGED","模板已更新，请重新准备材料");
        attachments.read(current,file);return new Prepared("已预填-"+filename,result);
    }
}
