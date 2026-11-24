package cn.workpanel.module.customer.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Map;

/** Pure customer-profile rules; no task, log or membership external calls. */
public record CustomerDraft(String kind,String name,String phone,String email,String externalId,String note,String status,Integer version) {
    public static final int MAX_NAME=200;
    public static final int MAX_NOTE=2000;
    public static CustomerDraft parse(Map<String,Object> body,boolean update) {
        if(update) Db.fields(body,"version","kind","name","phone","email","externalId","note","status");
        else Db.fields(body,"kind","name","phone","email","externalId","note");
        String kind=text(body.get("kind"),16,false).toUpperCase();
        if(!kind.equals("INDIVIDUAL")&&!kind.equals("ENTERPRISE")) throw ApiError.bad("INVALID_KIND","客户类型仅支持 INDIVIDUAL 或 ENTERPRISE");
        String name=text(body.get("name"),MAX_NAME,false);
        String phone=text(body.get("phone"),40,true);
        String email=text(body.get("email"),200,true);
        if(!email.isEmpty()&&!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) throw ApiError.bad("INVALID_EMAIL","邮箱格式无效");
        String externalId=text(body.get("externalId"),200,true);
        if(externalId.isEmpty()) externalId=null;
        String note=text(body.get("note"),MAX_NOTE,true);
        String status="ACTIVE";
        int version=0;
        if(update) {
            status=text(body.get("status"),16,true).toUpperCase();
            if(status.isEmpty()) status="ACTIVE";
            if(!status.equals("ACTIVE")&&!status.equals("ARCHIVED")) throw ApiError.bad("INVALID_STATUS","客户状态仅支持 ACTIVE 或 ARCHIVED");
            Object raw=body.get("version");
            if(!(raw instanceof Integer)||(Integer)raw<1) throw ApiError.bad("INVALID_VERSION","version 必须为正整数");
            version=(Integer)raw;
        }
        return new CustomerDraft(kind,name,phone,email,externalId,note,status,version);
    }
    public static LocalDate date(Object raw,String field) {
        try {
            if(!(raw instanceof String value)||!value.matches("\\d{4}-\\d{2}-\\d{2}")) throw new DateTimeParseException(field,"",0);
            LocalDate date=LocalDate.parse(value);
            if(date.getYear()<1900||date.getYear()>2100) throw new DateTimeParseException("range","",0);
            return date;
        } catch(DateTimeParseException e) { throw ApiError.bad("INVALID_DATE",field+"必须为1900–2100年的YYYY-MM-DD"); }
    }
    private static String text(Object raw,int max,boolean empty) {
        if(raw==null) { if(empty) return ""; throw ApiError.bad("INVALID_FIELD","需要文本字段"); }
        if(!(raw instanceof String value)) throw ApiError.bad("INVALID_FIELD","需要文本字段");
        String text=value.strip();
        if((!empty&&text.isEmpty())||text.codePointCount(0,text.length())>max) throw ApiError.bad("INVALID_FIELD","字段长度无效");
        return text;
    }
}
