package cn.workpanel.module.procedure.application;

import cn.workpanel.*;
import cn.workpanel.shared.application.*;
import cn.workpanel.module.procedure.infrastructure.ProcedureRepository;
import cn.workpanel.module.procedure.domain.ProcedureDocument;
import cn.workpanel.module.procedure.api.ProcedureAccess;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class ProcedureService {
    private final ProcedureRepository repo;private final CurrentActors actors;private final CommandKeys keys;private final ProcedureAccess access;private final ReviewApplicationService reviews;
    public ProcedureService(ProcedureRepository repo,CurrentActors actors,CommandKeys keys,ProcedureAccess access,ReviewApplicationService reviews) { this.repo=repo;this.actors=actors;this.keys=keys;this.access=access;this.reviews=reviews; }
    public Map<String,Object> list(Actor actor,String query,boolean drafts) {
        Actor a=actors.fresh(actor);if(drafts)a.requireAdmin();var rows=drafts?repo.drafts(a):access.search(a,query);return Map.of("items",rows,"total",rows.size());
    }
    public Map<String,Object> list(Actor actor,String query,boolean drafts,int cursor,int limit){Actor a=actors.fresh(actor);if(!drafts)return access.page(a,query,cursor,limit);a.requireAdmin();Business.page(cursor,limit);if(query.length()>200)throw ApiError.bad("INVALID_QUERY","查询内容过长");var rows=repo.drafts(a,query,cursor,limit+1);return Map.of("items",rows.stream().limit(limit).toList(),"total",rows.isEmpty()?0:rows.getFirst().get("total_count"),"nextCursor",rows.size()>limit?cursor+limit:-1);}
    public Map<String,Object> get(Actor actor,String id,boolean draft) {
        Actor a=actors.fresh(actor);if(!draft)return access.get(a,id);a.requireAdmin();var row=repo.document(a,id,false);
        var value=new LinkedHashMap<>(repo.json(repo.revision(a,id,((Number)row.get("version")).intValue()).get("body")));value.putAll(row);return value;
    }
    public Map<String,Object> compare(Actor actor,String id){Actor a=actors.fresh(actor);a.requireAdmin();var row=repo.document(a,id,false);var draft=get(a,id,true);Map<String,Object> published=Map.of();if(row.get("active_version") instanceof Number active && active.intValue()>0)published=repo.json(repo.revision(a,id,((Number)row.get("active_version")).intValue()).get("body"));return Map.of("draft",draft,"published",published);}
    public Map<String,Object> prepareTemplate(Actor actor,String id,Map<String,Object> body){Actor a=actors.fresh(actor);Db.fields(body,"version","reason");var source=access.get(a,id);if(!"TEMPLATE".equals(source.get("type")))throw ApiError.bad("INVALID_TEMPLATE","请选择公司模板");if(Db.version(body)!=((Number)source.get("version")).intValue())throw ApiError.conflict();String content=cn.workpanel.module.aiwork.infrastructure.TemplateRenderer.replace(Db.str(source,"content"),templateFields(a,body));return Map.of("id",id,"version",source.get("version"),"title",source.get("title"),"content",content,"attachmentIds",source.getOrDefault("attachmentIds",List.of()),"unfilled",content.contains("{{"));}
    public Map<String,String> templateFields(Actor actor,Map<String,Object> body){Actor a=actors.fresh(actor);String reason=Db.str(body,"reason");if(reason.length()>2000)throw ApiError.bad("INVALID_FIELD","事由最多2000字");return Map.of("姓名",Db.str(repo.user(a),"name"),"部门",a.department().isBlank()?"":Db.str(repo.department(a),"name"),"日期",java.time.LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).toString(),"事由",reason);}
    @Transactional public Map<String,Object> create(Actor actor,Map<String,Object> body,String key) {
        Actor a=actors.locked(actor);a.requireAdmin();var b=ProcedureDocument.validate(body);repo.validateScope(a,b);
        var receipt=keys.execute(a,"procedure.create",key,body,()->{String id=Db.id();repo.create(a,id,b);for(String f:Business.strings(b,"attachmentIds"))repo.bind(a,id,f);repo.audit(a,"PROCEDURE_DRAFT",id,b);return Map.of("id",id);});return get(a,Db.str(receipt,"id"),true);
    }
    @Transactional public Map<String,Object> revise(Actor actor,String id,Map<String,Object> body,String key) {
        Actor a=actors.locked(actor);a.requireAdmin();Db.fields(body,"version","candidate");var b=ProcedureDocument.validate(repo.json(body.get("candidate")));repo.validateScope(a,b);
        return keys.execute(a,"procedure.revise:"+id,key,body,()->{var old=repo.document(a,id,true);int v=Db.version(body);if(((Number)old.get("version")).intValue()!=v)throw ApiError.conflict();repo.version(a,id,v+1,b);repo.advance(a,id,v,v+1);for(String f:Business.strings(b,"attachmentIds"))repo.bind(a,id,f);return get(a,id,true);});
    }
    @Transactional public Map<String,Object> publish(Actor actor,String id,Map<String,Object> body,String key) {
        Actor a=actors.locked(actor);a.requireAdmin();Db.fields(body,"version","reason","withdraw");
        return keys.execute(a,"procedure.publish:"+id,key,body,()->{var old=repo.document(a,id,true);int v=Db.version(body);if(((Number)old.get("version")).intValue()!=v)throw ApiError.conflict();return reviews.create(a,"PROCEDURE",id,v,old,Map.of("withdraw",Boolean.TRUE.equals(body.get("withdraw"))),Db.required(body,"reason"));});
    }
}
