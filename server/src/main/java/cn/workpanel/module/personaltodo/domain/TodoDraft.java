package cn.workpanel.module.personaltodo.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.*;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.Map;

/** Pure private-todo rules. No task, review, organization traversal or IO. */
public record TodoDraft(String title,String note,LocalDate date,LocalDate endDate,String color,boolean completed,int version) {
    public static final String DEFAULT_COLOR="#F3A45D";
    public static final int MAX_SPAN_DAYS=366;
    public static TodoDraft parse(Map<String,Object> body, boolean update) {
        if(update) Db.fields(body,"title","note","date","endDate","color","completed","version");
        else Db.fields(body,"title","note","date","endDate","color");
        String title=text(body.get("title"),120,false);
        String note=body.containsKey("note")?text(body.get("note"),2000,true):"";
        if(update && !(body.get("completed") instanceof Boolean))
            throw ApiError.bad("INVALID_BOOLEAN","completed 必须为布尔值");
        int version=0;
        if(update) {
            Object raw=body.get("version");
            if(!(raw instanceof Integer) || (Integer)raw<1)
                throw ApiError.bad("INVALID_VERSION","version 必须为正整数");
            version=(Integer)raw;
        }
        LocalDate date=date(body.get("date"));
        LocalDate endDate=body.get("endDate")==null?date:date(body.get("endDate"));
        if(endDate.isBefore(date))
            throw ApiError.bad("INVALID_DATE_RANGE","结束日期不能早于开始日期");
        if(ChronoUnit.DAYS.between(date,endDate)>MAX_SPAN_DAYS)
            throw ApiError.bad("INVALID_DATE_RANGE","事项跨度不能超过"+MAX_SPAN_DAYS+"天");
        String color=body.get("color")==null?DEFAULT_COLOR:color(body.get("color"));
        return new TodoDraft(title,note,date,endDate,color,update&&(Boolean)body.get("completed"),version);
    }
    private static String text(Object raw,int max,boolean empty) {
        if(!(raw instanceof String)) throw ApiError.bad("INVALID_FIELD","需要文本字段");
        String value=((String)raw).strip();
        if((!empty&&value.isBlank())||value.codePointCount(0,value.length())>max)
            throw ApiError.bad("INVALID_FIELD","标题为1–120字，备注最多2000字");
        return value;
    }
    private static String color(Object raw) {
        if(!(raw instanceof String value)||!value.matches("^#[0-9A-Fa-f]{6}$"))
            throw ApiError.bad("INVALID_COLOR","颜色须为#RRGGBB");
        return value.toUpperCase();
    }
    public static LocalDate date(Object raw) {
        try {
            if(!(raw instanceof String value)||!value.matches("\\d{4}-\\d{2}-\\d{2}")) throw new DateTimeParseException("date","",0);
            LocalDate date=LocalDate.parse((String)raw);
            if(date.getYear()<1900||date.getYear()>2100) throw new DateTimeParseException("range","",0);
            return date;
        } catch(DateTimeParseException e) { throw ApiError.bad("INVALID_DATE","日期须为1900–2100年的有效YYYY-MM-DD"); }
    }
    public static YearMonth month(String value) {
        try {
            if(value==null||!value.matches("\\d{4}-\\d{2}")) throw new DateTimeParseException("month","",0);
            YearMonth month=YearMonth.parse(value);
            if(month.getYear()<1900||month.getYear()>2100) throw new DateTimeParseException("range","",0);
            return month;
        } catch(DateTimeParseException e) { throw ApiError.bad("INVALID_MONTH","月份须为1900–2100年的有效YYYY-MM"); }
    }
}
