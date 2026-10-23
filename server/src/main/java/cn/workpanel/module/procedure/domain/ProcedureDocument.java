package cn.workpanel.module.procedure.domain;

import cn.workpanel.*;
import cn.workpanel.module.task.AcceptanceChecklist;
import java.time.*;
import java.util.*;

public final class ProcedureDocument {
    private ProcedureDocument() {}
    public static Map<String,Object> validate(Map<String,Object> raw) {
        Db.fields(raw,"title","type","content","scopeKind","scopeId","effectiveFrom","effectiveTo","attachmentIds","workflow","acceptanceChecklist");
        var b=new LinkedHashMap<>(raw);
        if(Db.required(b,"title").length()>200) throw ApiError.bad("INVALID_PROCEDURE","标题过长");
        Db.required(b,"content");
        if(!Set.of("POLICY","PROCEDURE","TEMPLATE").contains(Db.required(b,"type"))) throw ApiError.bad("INVALID_PROCEDURE","资料类型无效");
        b.putIfAbsent("scopeKind","COMPANY");
        if(!Set.of("COMPANY","DEPARTMENT","TEAM").contains(Db.str(b,"scopeKind"))) throw ApiError.bad("INVALID_PROCEDURE","适用范围无效");
        if(!Db.str(b,"scopeKind").equals("COMPANY")) Db.required(b,"scopeId");
        else b.remove("scopeId");
        b.putIfAbsent("effectiveFrom",Instant.now().toString());
        try { var from=OffsetDateTime.parse(Db.str(b,"effectiveFrom")); if(b.get("effectiveTo")!=null&&!OffsetDateTime.parse(Db.str(b,"effectiveTo")).isAfter(from)) throw new IllegalArgumentException(); }
        catch(Exception e) { throw ApiError.bad("INVALID_PERIOD","需要有效的生效日期和失效日期"); }
        var files=Business.strings(b,"attachmentIds");if(files.size()>5) throw ApiError.bad("INVALID_PROCEDURE","模板附件最多5个");b.put("attachmentIds",files);
        if(b.containsKey("workflow")&&!Set.of("CREATE_TASK","SUBMIT_DELIVERY","REQUEST_RESCHEDULE","REQUEST_REASSIGNMENT").contains(Db.str(b,"workflow"))) throw ApiError.bad("UNSUPPORTED_ACTION","尚不支持这项办理");
        b.put("acceptanceChecklist",AcceptanceChecklist.normalize(b.get("acceptanceChecklist")));
        return b;
    }
}
