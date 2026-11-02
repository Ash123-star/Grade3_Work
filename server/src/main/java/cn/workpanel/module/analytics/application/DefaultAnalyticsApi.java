package cn.workpanel.module.analytics.application;

import cn.workpanel.*;
import cn.workpanel.contract.ActorContext;
import cn.workpanel.module.analytics.api.AnalyticsApi;
import cn.workpanel.shared.application.CurrentActors;
import org.springframework.stereotype.Service;
import java.util.Map;

/** 跨模块分析端口；身份重新从数据库读取，禁止调用者伪造组织权限。 */
@Service
public class DefaultAnalyticsApi implements AnalyticsApi {
    private final CurrentActors actors;
    private final AnalyticsService service;
    public DefaultAnalyticsApi(CurrentActors actors,AnalyticsService service) { this.actors=actors; this.service=service; }
    private AnalyticsQuery query(Map<String,Object> q) {
        return new AnalyticsQuery(Db.required(q,"date"),text(q,"period"),text(q,"groupBy"),text(q,"departmentId"),text(q,"teamId"),text(q,"ownerId"));
    }
    private String text(Map<String,Object> q,String key) {
        if(!q.containsKey(key)) return null;
        if(!(q.get(key) instanceof String value)) throw ApiError.bad("INVALID_FIELD",key+" 必须为文本");
        return value;
    }
    private int number(Map<String,Object> q,String key,int fallback) {
        if(!q.containsKey(key)) return fallback;
        Object value=q.get(key); if(!(value instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<0) throw ApiError.bad("INVALID_PAGE",key+" 无效");
        return n.intValue();
    }
    public Map<String,Object> statistics(ActorContext actor,Map<String,Object> q) {
        Db.fields(q,"date","period","groupBy","departmentId","teamId","ownerId"); return service.statistics(actors.fresh(actor),query(q));
    }
    public Map<String,Object> details(ActorContext actor,Map<String,Object> q) {
        Db.fields(q,"date","period","groupBy","departmentId","teamId","ownerId","metric","groupId","bucket","cursor","limit");
        return service.details(actors.fresh(actor),query(q),Db.required(q,"metric"),text(q,"groupId"),text(q,"bucket"),number(q,"cursor",0),number(q,"limit",30));
    }
    public String export(ActorContext actor,Map<String,Object> q) {
        Db.fields(q,"date","period","groupBy","departmentId","teamId","ownerId","resource"); return service.export(actors.fresh(actor),query(q),Db.required(q,"resource"));
    }
}
