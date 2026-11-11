package cn.workpanel.module.analytics.application;

import cn.workpanel.*;
import cn.workpanel.module.analytics.infrastructure.AnalyticsRepository;
import cn.workpanel.module.attachment.application.GeneratedFiles;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.*;
import org.springframework.transaction.support.TransactionTemplate;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** 一致快照构建结束后再访问OSS；交付时重新鉴权，避免快照事务掩盖权限撤回。 */
@Service
public class AnalyticsExportService {
    private final AnalyticsRepository repository;private final GeneratedFiles generated;private final CurrentActors actors;private final TransactionTemplate snapshot;
    public AnalyticsExportService(AnalyticsRepository repository,GeneratedFiles generated,CurrentActors actors,PlatformTransactionManager manager){
        this.repository=repository;this.generated=generated;this.actors=actors;snapshot=new TransactionTemplate(manager);
        snapshot.setReadOnly(true);snapshot.setIsolationLevel(TransactionDefinition.ISOLATION_REPEATABLE_READ);snapshot.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }
    private record Prepared(byte[] bytes,List<Map<String,Object>> sources){}
    public GeneratedFiles.Result export(Actor actor,AnalyticsQuery query,String resource){
        if(!Set.of("logs","tasks").contains(resource))throw ApiError.bad("INVALID_RESOURCE","resource: logs/tasks");
        Prepared prepared=snapshot.execute(s->{
            Actor current=actors.fresh(actor);repository.authorize(current,query,null);var rows=repository.export(repository.facts(current,query),resource);
            if(rows.size()>10000)throw ApiError.bad("EXPORT_TOO_LARGE","导出超过10000条，请缩小范围");
            var csv=new StringBuilder("\ufeffid,type,title_or_date,owner_id,owner_name,version,group_id,group_name,occurred_at\r\n");var sources=new ArrayList<Map<String,Object>>();
            for(var row:rows){
                sources.add(Map.of("type",resource.equals("logs")?"LOG":"TASK","id",row.get("id"),"version",row.get("version")));
                var cells=new ArrayList<String>();for(String field:List.of("id","resource","title","owner_id","owner_name","version","group_id","group_name","occurred_at"))cells.add(AnalyticsService.csv(row.get(field)));
                csv.append(String.join(",",cells)).append("\r\n");
            }
            return new Prepared(csv.toString().getBytes(StandardCharsets.UTF_8),sources);
        });
        return generated.create(actor,"EXPORT",resource+".csv",Objects.requireNonNull(prepared).bytes(),prepared.sources());
    }
}
