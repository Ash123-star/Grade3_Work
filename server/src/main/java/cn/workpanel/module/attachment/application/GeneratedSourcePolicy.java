package cn.workpanel.module.attachment.application;

import cn.workpanel.*;
import cn.workpanel.module.procedure.api.ProcedureAccess;
import org.springframework.stereotype.Component;
import java.util.*;

/** 已生成文件不是权限快照：每次使用均重验全部来源及当前版本。 */
@Component
public class GeneratedSourcePolicy {
    private final Db db;private final Business business;private final ProcedureAccess procedures;private final cn.workpanel.shared.application.CurrentActors actors;
    public GeneratedSourcePolicy(Db db,Business business,ProcedureAccess procedures,cn.workpanel.shared.application.CurrentActors actors){this.db=db;this.business=business;this.procedures=procedures;this.actors=actors;}
    public void attachment(Actor a,String id){
        var rows=db.rows("SELECT owner_id,sources FROM generated_files WHERE company_id=? AND attachment_id=?",a.company(),id);
        for(var row:rows){if(!a.id().equals(row.get("owner_id")))throw ApiError.forbidden();validate(a,db.read(row.get("sources")));}
    }
    public void validate(Actor a,Map<String,Object> sources){
        Object input=sources.get("items");if(!(input instanceof List<?> items))throw ApiError.notFound();
        if(sources.containsKey("fingerprint")&&!actors.fingerprint(a).equals(sources.get("fingerprint")))throw ApiError.forbidden();
        for(Object item:items){
            var source=db.read(item);String type=Db.str(source,"type"),id=Db.str(source,"id");
            Map<String,Object> current=switch(type){case "TASK"->business.task(a,id,false);case "LOG"->business.log(a,id,false);case "PROCEDURE"->procedures.get(a,id);default->throw ApiError.notFound();};
            if(source.get("version") instanceof Number expected&&(!(current.get("version") instanceof Number actual)||actual.longValue()!=expected.longValue()))throw new ApiError(409,"SOURCE_CHANGED","文件来源已更新，请重新生成");
        }
    }
}
