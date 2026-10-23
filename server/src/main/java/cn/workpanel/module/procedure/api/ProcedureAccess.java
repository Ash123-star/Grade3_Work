package cn.workpanel.module.procedure.api;

import cn.workpanel.*;
import cn.workpanel.module.procedure.infrastructure.ProcedureRepository;
import cn.workpanel.module.procedure.domain.ProcedureSearch;
import org.springframework.stereotype.Component;
import java.util.*;

/** 正式资料查询的公共端口，维护草稿与对外有效资料严格分离。 */
@Component
public class ProcedureAccess {
    private final ProcedureRepository repo;
    public ProcedureAccess(ProcedureRepository repo) { this.repo=repo; }
    public List<Map<String,Object>> search(Actor a,String query) {
        if(query.length()>200) throw ApiError.bad("INVALID_QUERY","查询内容过长");
        return repo.published(a,query).stream().map(this::dto).toList();
    }
    public Map<String,Object> page(Actor a,String query,int cursor,int limit){Business.page(cursor,limit);if(query.length()>200)throw ApiError.bad("INVALID_QUERY","查询内容过长");var rows=repo.published(a,query,cursor,limit+1);return Map.of("items",rows.stream().limit(limit).map(this::dto).toList(),"total",rows.isEmpty()?0:rows.getFirst().get("total_count"),"nextCursor",rows.size()>limit?cursor+limit:-1);}
    /** 仅返回当前输入命中的正式来源和定位；不允许模型凭ID另外检索未提供资料。 */
    public List<Map<String,Object>> retrieve(Actor a,String query){return repo.published(a,query,0,8).stream().map(this::dto).map(b->{b.put("excerpts",ProcedureSearch.excerpts(Db.str(b,"content"),query));return b;}).toList();}
    public List<Map<String,Object>> conflicts(Actor a,Map<String,Object> source){return repo.peers(a,source).stream().map(this::dto).filter(other->!other.get("id").equals(source.get("id"))&&ProcedureSearch.conflicts(source,other)).toList();}
    private Map<String,Object> dto(Map<String,Object> row){var b=new LinkedHashMap<>(repo.json(row.get("body")));b.put("id",row.get("id"));b.put("version",row.get("active_version"));return b;}
    public Map<String,Object> get(Actor a,String id) { var r=repo.visible(a,id);var b=new LinkedHashMap<>(repo.json(r.get("body")));b.put("id",id);b.put("version",r.get("active_version"));return b; }
    public void validateSources(Actor a,List<Map<String,Object>> sources) {
        validateVersions(a,sources);
        var ids=sources.stream().map(s->Db.str(s,"id")).collect(java.util.stream.Collectors.toSet());
        for(var source:sources)for(var conflict:conflicts(a,get(a,Db.str(source,"id"))))if(!ids.contains(Db.str(conflict,"id")))throw new ApiError(409,"SOURCE_CHANGED","正式资料出现冲突，请重新核对");
    }
    public void validateVersions(Actor a,List<Map<String,Object>> sources){for(var source:sources)if(((Number)get(a,Db.str(source,"id")).get("version")).intValue()!=((Number)source.get("version")).intValue())throw new ApiError(409,"SOURCE_CHANGED","依据已更新，请重新核对");}
    public void validateForExecution(Actor a,List<Map<String,Object>> sources){validateSources(a,sources);for(var source:sources)if(!conflicts(a,get(a,Db.str(source,"id"))).isEmpty())throw new ApiError(409,"SOURCE_CONFLICT","正式资料存在冲突，请先核对依据");}
    /** 必须在业务提交事务中使用，发布/撤回与依据消费按资料行锁确定先后。 */
    public void lockForExecution(Actor a,List<Map<String,Object>> sources){repo.lockSources(a,sources);validateForExecution(a,sources);}
}
