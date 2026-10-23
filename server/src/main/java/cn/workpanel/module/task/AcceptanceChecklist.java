package cn.workpanel.module.task;

import cn.workpanel.*;
import java.util.*;

/** 交付要求的输入契约。推断条目只能作建议，不能成为强制条件。 */
public final class AcceptanceChecklist {
    private AcceptanceChecklist() {}
    public static List<Map<String,Object>> normalize(Object value) {
        if(value==null) return List.of();
        if(!(value instanceof List<?> rows)||rows.size()>30) throw ApiError.bad("INVALID_CHECKLIST","交付清单最多30项");
        var ids=new HashSet<String>(); var result=new ArrayList<Map<String,Object>>();
        for(Object row:rows) {
            if(!(row instanceof Map<?,?> raw)) throw ApiError.bad("INVALID_CHECKLIST","交付要求无效");
            var m=new LinkedHashMap<String,Object>(); raw.forEach((k,v)->m.put(k.toString(),v));
            Db.fields(m,"id","title","required","category","fileName","field","expected","unit","currency","source");
            String id=Db.str(m,"id"); if(id.isBlank()) id="item-"+(result.size()+1);
            if(!ids.add(id)||id.length()>100) throw ApiError.bad("INVALID_CHECKLIST","交付要求编号重复或过长");
            String title=Db.required(m,"title"); if(title.length()>300) throw ApiError.bad("INVALID_CHECKLIST","交付要求过长");
            String category=Db.str(m,"category"); if(category.isBlank()) category="CONFIRMED";
            if(!Set.of("CONFIRMED","INFERRED").contains(category)) throw ApiError.bad("INVALID_CHECKLIST","交付要求类别无效");
            if(m.containsKey("required")&&!(m.get("required") instanceof Boolean)) throw ApiError.bad("INVALID_CHECKLIST","required必须为布尔值");
            m.put("id",id);m.put("title",title);m.put("category",category);m.put("required",!category.equals("INFERRED")&&!Boolean.FALSE.equals(m.get("required")));
            for(String k:List.of("fileName","field","expected","unit","currency","source")) if(m.containsKey(k)&&(!(m.get(k) instanceof String s)||s.length()>1000)) throw ApiError.bad("INVALID_CHECKLIST","交付要求字段无效");
            result.add(Map.copyOf(m));
        }
        return List.copyOf(result);
    }
}
