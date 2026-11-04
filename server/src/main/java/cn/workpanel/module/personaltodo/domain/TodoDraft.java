package cn.workpanel.module.personaltodo.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.*;
import java.time.format.DateTimeParseException;
import java.util.Map;

/** Pure private-todo rules. No task, review, organization traversal or IO. */
public record TodoDraft(String title, String note, LocalDate date, boolean completed, int version) {
    public static TodoDraft parse(Map<String,Object> body, boolean update) {
        if(update) Db.fields(body,"title","note","date","completed","version");
        else Db.fields(body,"title","note","date");
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
        return new TodoDraft(title,note,date(body.get("date")),update&&(Boolean)body.get("completed"),version);
    }
    private static String text(Object raw,int max,boolean empty) {
        if(!(raw instanceof String)) throw ApiError.bad("INVALID_FIELD","需要文本字段");
        String value=((String)raw).strip();
        if((!empty&&value.isBlank())||value.codePointCount(0,value.length())>max)
            throw ApiError.bad("INVALID_FIELD","标题为1–120字，备注最多2000字");
        return value;
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
