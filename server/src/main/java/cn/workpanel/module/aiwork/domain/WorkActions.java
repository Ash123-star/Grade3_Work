package cn.workpanel.module.aiwork.domain;

import cn.workpanel.Db;
import cn.workpanel.shared.application.CommandKeys;
import java.util.*;

/** 动作类型是语义身份的一部分；授权标记不是业务内容，不能改变去重结果。 */
public final class WorkActions {
    private WorkActions() {}
    public static String fingerprint(Db db,String action,Map<String,Object> payload) {
        var body=new LinkedHashMap<>(payload);
        body.keySet().removeAll(Set.of("explicit","confirmed","preauthorized"));
        return Db.hash(db.write(CommandKeys.canonical(Map.of("action",action,"payload",body))));
    }
    /** 依赖只能指向本计划中更早的步骤，天然排除环与跨事项引用。 */
    public static List<String> dependencies(Object raw,int position) {
        if(raw==null)return List.of();
        if(!(raw instanceof List<?> list)||list.size()>9)throw invalid();
        var result=new LinkedHashSet<String>();
        for(Object entry:list){if(!(entry instanceof Number n)||n.doubleValue()!=n.intValue()||n.intValue()<1||n.intValue()>=position)throw invalid();result.add("action-"+n.intValue());}
        return List.copyOf(result);
    }
    private static cn.workpanel.ApiError invalid(){return cn.workpanel.ApiError.bad("AI_SCHEMA","办理顺序需要重新整理，请补充具体要求");}
}
