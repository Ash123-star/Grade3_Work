package cn.workpanel.module.dashboard.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.util.Map;

/** 公司展示候选与最终应用共享输入规则。 */
public final class CompanyItemPolicy {
    private CompanyItemPolicy() { }
    public static void validate(Map<String,Object> body) {
        String title=Db.required(body,"title");
        if(title.length()>200) throw ApiError.bad("INVALID_TITLE","标题不能超过200字");
        if(body.containsKey("text")&&(!(body.get("text") instanceof String text)||text.length()>20000)) throw ApiError.bad("INVALID_TEXT","正文不能超过20000字");
        for(String key:java.util.List.of("pinned","archived")) if(body.containsKey(key)&&!(body.get(key) instanceof Boolean)) throw ApiError.bad("INVALID_BOOLEAN",key+"必须为布尔值");
        if(body.containsKey("position")&&(!(body.get("position") instanceof Number number)||!Double.isFinite(number.doubleValue())||number.doubleValue()!=number.intValue()||number.intValue()<0||number.intValue()>10000)) throw ApiError.bad("INVALID_POSITION","排序位置需为0到10000的整数");
    }
    public static String reason(Map<String,Object> body) {
        String reason=Db.required(body,"reason");
        if(reason.length()>2000) throw ApiError.bad("INVALID_REASON","修改理由不能超过2000字");
        return reason;
    }
}
