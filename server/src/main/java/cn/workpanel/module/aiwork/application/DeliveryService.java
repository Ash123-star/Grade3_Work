package cn.workpanel.module.aiwork.application;

import cn.workpanel.*;
import cn.workpanel.module.aiwork.domain.*;
import cn.workpanel.module.aiwork.infrastructure.FileExtractor;
import cn.workpanel.module.attachment.application.AttachmentApplicationService;
import cn.workpanel.module.task.*;
import cn.workpanel.module.task.api.TaskApi;
import cn.workpanel.module.review.api.ReviewActors;
import cn.workpanel.shared.application.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import java.util.*;

/** 检查不改变任务；交付绑定、FEEDBACK、回执在单一数据库事务内提交。 */
@Service
public class DeliveryService {
    private final Db db;private final CurrentActors actors;private final AttachmentApplicationService attachments;private final FileExtractor extractor;private final TaskApi tasks;private final CommandKeys keys;private final TransactionTemplate tx;private final cn.workpanel.module.procedure.api.ProcedureAccess procedures;
    public DeliveryService(Db db,CurrentActors actors,AttachmentApplicationService attachments,FileExtractor extractor,TaskApi tasks,CommandKeys keys,PlatformTransactionManager manager,cn.workpanel.module.procedure.api.ProcedureAccess procedures){this.db=db;this.actors=actors;this.attachments=attachments;this.extractor=extractor;this.tasks=tasks;this.keys=keys;this.tx=new TransactionTemplate(manager);this.procedures=procedures;}
    public Map<String,Object> check(Actor actor,String taskId,Map<String,Object> body,String key){
        Db.fields(body,"taskVersion","attachmentIds");Actor a=actors.fresh(actor);var task=TaskAccess.readable(db,a,taskId,false);requireVersion(task,body);validateSources(a,task);var ids=Business.strings(body,"attachmentIds");attachments.intake(a,ids);
        var files=ids.stream().map(id->extractor.extract(a,id)).toList();var checklist=AcceptanceChecklist.normalize(db.read(task.get("body")).get("acceptanceChecklist"));var report=DeliveryRules.check(checklist,files);
        return tx.execute(status->{Actor current=actors.locked(a);var live=TaskAccess.readable(db,current,taskId,true);requireVersion(live,body);validateSources(current,live);return keys.execute(current,"delivery.check:"+taskId,key,body,()->{
            String id=Db.id();var manifest=files.stream().map(f->Map.of("id",f.get("id"),"hash",f.get("hash"),"parserVersion",f.get("parserVersion"))).toList();String fingerprint=fingerprint(live,manifest);
            db.update("INSERT INTO task_delivery_checks(id,company_id,task_id,owner_id,task_version,fingerprint,state,manifest,body) VALUES (?,?,?,?,?,?,?,?::jsonb,?::jsonb)",id,current.company(),taskId,current.id(),live.get("version"),fingerprint,report.get("state"),db.write(Map.of("files",manifest)),db.write(report));
            int pos=0;for(var f:maps(report,"findings"))db.update("INSERT INTO task_delivery_findings(company_id,check_id,position,body) VALUES (?,?,?,?::jsonb)",a.company(),id,++pos,db.write(f));
            return get(current,taskId,id);
        });});
    }
    /** 报告每次读取重查来源、材料及规则快照；历史通过不得在失效后继续呈现为当前通过。 */
    public Map<String,Object> get(Actor actor,String taskId,String id){
        Actor a=actors.fresh(actor);var task=TaskAccess.readable(db,a,taskId,false);
        var row=db.one("SELECT * FROM task_delivery_checks WHERE company_id=? AND task_id=? AND id=? AND owner_id=?",a.company(),taskId,id,a.id());
        var manifest=maps(db.read(row.get("manifest")),"files");boolean valid=fingerprint(task,manifest).equals(row.get("fingerprint"));
        try{validateSources(a,task);for(var file:manifest)if(!FileExtractor.VERSION.equals(file.get("parserVersion"))||!AttachmentApplicationService.hash((byte[])attachments.owned(a,Db.str(file,"id")).get("data")).equals(file.get("hash")))valid=false;}
        catch(ApiError error){valid=false;}
        var result=new LinkedHashMap<>(valid?db.read(row.get("body")):Map.of("state","STALE","summary","交付要求或材料已更新，请重新检查","findings",List.of()));
        result.put("id",id);result.put("version",row.get("version"));result.put("taskVersion",row.get("task_version"));result.put("snapshotValid",valid);result.put("attachmentIds",manifest.stream().map(f->f.get("id")).toList());return result;
    }
    @Transactional public Map<String,Object> submit(Actor actor,String taskId,Map<String,Object> body,String key){
        Db.fields(body,"taskVersion","checkId","checkVersion","attachmentIds","mode","text");Actor a=actors.locked(actor);var task=TaskAccess.readable(db,a,taskId,true);String checkId=Db.required(body,"checkId");
        // 重放之前仍检查当前任务读取权；重放本身不重复 FEEDBACK。
        return keys.execute(a,"delivery.submit:"+taskId,key,body,()->{
            requireVersion(task,body);validateSources(a,task,true);var row=db.one("SELECT * FROM task_delivery_checks WHERE company_id=? AND task_id=? AND id=? AND owner_id=?",a.company(),taskId,checkId,a.id());
            if(!(body.get("checkVersion") instanceof Number n)||n.intValue()!=((Number)row.get("version")).intValue())throw ApiError.conflict();
            var manifest=maps(db.read(row.get("manifest")),"files");var ids=Business.strings(body,"attachmentIds");
            if(!new HashSet<>(ids).equals(new HashSet<>(manifest.stream().map(f->Db.str(f,"id")).toList())))throw stale();
            for(var file:manifest)if(!FileExtractor.VERSION.equals(file.get("parserVersion"))||!AttachmentApplicationService.hash((byte[])attachments.owned(a,Db.str(file,"id")).get("data")).equals(file.get("hash")))throw stale();
            if(!fingerprint(task,manifest).equals(row.get("fingerprint")))throw stale();
            String mode=Db.required(body,"mode"),text=Db.required(body,"text");if(!Set.of("CHECKED","MANUAL").contains(mode))throw ApiError.bad("INVALID_MODE","请选择提交方式");
            if(mode.equals("CHECKED")&&!row.get("state").equals("PASS"))throw new ApiError(409,"CHECK_NOT_PASSED","请补充材料后再提交");
            // 人工核对不能绕过已确认的必交材料硬约束。
            if(mode.equals("MANUAL")&&maps(db.read(row.get("body")),"findings").stream().anyMatch(f->f.get("state").equals("NEEDS_FIX")))throw new ApiError(409,"REQUIRED_MATERIAL_MISSING","请先补齐交付材料");
            var result=tasks.appendEvent(ReviewActors.context(a),taskId,Map.of("type","FEEDBACK","version",body.get("taskVersion"),"text",text));
            String id=Db.id();long sequence=db.count("SELECT max(sequence) FROM task_events WHERE task_id=?",taskId);
            db.update("INSERT INTO task_deliveries(id,company_id,task_id,actor_id,check_id,event_sequence,mode,text) VALUES (?,?,?,?,?,?,?,?)",id,a.company(),taskId,a.id(),checkId,sequence,mode,text);
            for(var file:manifest){String f=Db.str(file,"id");db.update("INSERT INTO task_delivery_files(company_id,delivery_id,attachment_id,file_hash) VALUES (?,?,?,?)",a.company(),id,f,file.get("hash"));attachments.bind(a,f,"DELIVERY",id);}
            db.audit(a,"TASK_DELIVERY_SUBMITTED",id,Map.of(),Map.of("taskId",taskId,"checkId",checkId,"mode",mode),text);
            return Map.of("id",id,"taskId",taskId,"taskVersion",result.get("version"),"summary","已提交，等待验收");
        });
    }
    private void validateSources(Actor a,Map<String,Object> task){
        validateSources(a,task,false);
    }
    private void validateSources(Actor a,Map<String,Object> task,boolean lock){
        var sources=new ArrayList<Map<String,Object>>();
        for(var item:AcceptanceChecklist.normalize(db.read(task.get("body")).get("acceptanceChecklist"))){String source=Db.str(item,"source");if(!source.startsWith("procedure:"))continue;int separator=source.lastIndexOf('@');if(separator<=10)throw stale();try{sources.add(Map.of("id",source.substring(10,separator),"version",Integer.parseInt(source.substring(separator+1))));}catch(NumberFormatException e){throw stale();}}
        if(lock)procedures.lockForExecution(a,sources);else procedures.validateSources(a,sources);
    }
    private String fingerprint(Map<String,Object> t,Object manifest){return Db.hash(db.write(CommandKeys.canonical(Map.of("taskVersion",t.get("version"),"body",t.get("body"),"files",manifest,"parserVersion",FileExtractor.VERSION,"rules",DeliveryRules.VERSION))));}
    private static void requireVersion(Map<String,Object> task,Map<String,Object> b){if(!(b.get("taskVersion") instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()!=((Number)task.get("version")).intValue())throw ApiError.conflict();}
    private static ApiError stale(){return new ApiError(409,"CHECK_STALE","材料或交付要求已更新，请重新检查");}
    @SuppressWarnings("unchecked")public static List<Map<String,Object>> maps(Map<String,Object> b,String k){return b.get(k) instanceof List<?> list?(List<Map<String,Object>>)list:List.of();}
}
