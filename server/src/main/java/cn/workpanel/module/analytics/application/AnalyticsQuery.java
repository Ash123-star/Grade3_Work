package cn.workpanel.module.analytics.application;

import cn.workpanel.*;
import java.time.LocalDate;
import java.util.*;

/** 汇总、钻取及导出共享的业务日期和组织筛选，所有 SQL 值都作为绑定参数。 */
public record AnalyticsQuery(String date,String period,String groupBy,String departmentId,String teamId,String ownerId) {
    public AnalyticsQuery {
        period=period==null?"week":period;
        groupBy=groupBy==null?"department":groupBy;
        if(!Set.of("department","team","person").contains(groupBy)) throw ApiError.bad("INVALID_GROUP","groupBy: department/team/person");
        departmentId=filter(departmentId); teamId=filter(teamId); ownerId=filter(ownerId);
        Business.range(date,period);
    }
    private static String filter(String value) {
        if(value==null) return null;
        if(value.isBlank()||value.length()>100) throw ApiError.bad("INVALID_FILTER","组织筛选必须为非空有效 ID");
        return value;
    }
    public Business.Range range() { return Business.range(date,period); }
    public String groupColumn() { return switch(groupBy) { case "team" -> "team_id"; case "person" -> "id"; default -> "department_id"; }; }
    public Map<String,Object> view() {
        var result=new LinkedHashMap<String,Object>(); result.put("date",date); result.put("period",period); result.put("groupBy",groupBy);
        result.put("departmentId",departmentId); result.put("teamId",teamId); result.put("ownerId",ownerId); return result;
    }
    public LocalDate bucket(String value) {
        if(value==null) return null;
        try {
            if(!value.matches("\\d{4}-\\d{2}-\\d{2}")) throw new IllegalArgumentException();
            LocalDate day=LocalDate.parse(value);
            if(day.isBefore(range().first())||!day.isBefore(range().end())) throw new IllegalArgumentException();
            return day;
        } catch(Exception error) { throw ApiError.bad("INVALID_BUCKET","bucket 必须是查询区间内的 YYYY-MM-DD"); }
    }
}
