package cn.workpanel.module.task;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.DateTimeException;
import java.time.OffsetDateTime;
import java.util.*;

/** 派发请求的字段白名单、服务端字段拒绝、默认值与去重排序；纯函数，不访问数据库。 */
public final class TaskDraftNormalizer {
    private TaskDraftNormalizer() {}
    static final Set<String> ALLOWED=Set.of("title","participants","startAt","deadline","group","content","urgency","labelId","attachments","ownerId","collaborators","progressNote");
    static final Set<String> SERVER_MANAGED=Set.of("id","issuerId","phase","status","state","version","completion","completed","progress","createdAt");
    static final Set<String> URGENCY=Set.of("URGENT","NORMAL","LOW");
    static final int MAX_REFERENCES=100;

    public static TaskDraft normalize(Map<String,Object> raw) {
        for(String key:raw.keySet()) if(SERVER_MANAGED.contains(key)) throw ApiError.bad("SERVER_MANAGED_FIELD","字段由服务端管理: "+key);
        Db.fields(raw,ALLOWED.toArray(String[]::new));
        String title=Db.required(raw,"title"); if(title.length()>200) throw ApiError.bad("TITLE_LENGTH","标题过长");
        var participants=new TreeSet<>(ids(raw,"participants"));
        // 仅兼容尚未升级的写入方；规范化结果不保留负责人/协作人字段。
        if(participants.isEmpty()) { participants.add(Db.required(raw,"ownerId")); participants.addAll(ids(raw,"collaborators")); }
        if(participants.isEmpty()) throw ApiError.bad("INVALID_LIST","至少需要一名参与人");
        String deadline=Db.required(raw,"deadline");
        try { OffsetDateTime.parse(deadline); } catch(DateTimeException e) { throw ApiError.bad("INVALID_DATE","deadline 必须带时区"); }
        String startAt=text(raw,"startAt");
        if(startAt!=null) try { OffsetDateTime.parse(startAt); } catch(DateTimeException e) { throw ApiError.bad("INVALID_DATE","startAt 必须带时区"); }
        Object u=raw.getOrDefault("urgency","NORMAL");
        if(!(u instanceof String urgency)||!URGENCY.contains(urgency)) throw ApiError.bad("INVALID_URGENCY","urgency: URGENT/NORMAL/LOW");
        String content=text(raw,"content");
        String legacyProgress=text(raw,"progressNote");
        if(legacyProgress!=null) content=(content==null?"":content)+(content==null||content.isEmpty()?"":"\n\n")+legacyProgress;
        String labelId=text(raw,"labelId");
        return new TaskDraft(title,List.copyOf(participants),startAt,deadline,urgency,text(raw,"group"),content,labelId,List.copyOf(new TreeSet<>(ids(raw,"attachments"))));
    }

    /** v2 摘要：基于规范化内容，顺序与重复不影响结果。 */
    public static String hash(Db db,TaskDraft draft) { return Db.hash(db.write(draft.body())); }

    /** v1 摘要：V4 之前的算法，原始请求补默认紧急度后按键排序。 */
    public static String legacyHash(Db db,Map<String,Object> raw) {
        var c=new LinkedHashMap<>(raw); c.putIfAbsent("urgency","NORMAL"); return Db.hash(db.write(new TreeMap<>(c)));
    }

    static String text(Map<String,Object> raw,String key) {
        if(!raw.containsKey(key)||raw.get(key)==null) return null;
        if(!(raw.get(key) instanceof String s)||s.length()>20000) throw ApiError.bad("INVALID_FIELD","需要有效文本: "+key);
        return s;
    }

    static List<String> ids(Map<String,Object> raw,String key) {
        Object o=raw.get(key); if(o==null) return List.of();
        if(!(o instanceof List<?> list)||list.size()>MAX_REFERENCES||list.stream().anyMatch(x->!(x instanceof String s)||s.isBlank())) throw ApiError.bad("INVALID_LIST","列表无效: "+key);
        return list.stream().map(Object::toString).toList();
    }
}
