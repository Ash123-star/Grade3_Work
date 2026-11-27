package cn.workpanel.module.customer.domain;

import cn.workpanel.ApiError;
import cn.workpanel.Db;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.*;

/** Pure customer-profile rules; no task, log or membership external calls. */
public record CustomerDraft(String kind,String name,String phone,String email,String externalId,String note,String status,
                            int version, String ownerId, boolean ownerProvided, List<Contact> contacts) {
    public record Contact(String id, String name, String role, String phone, String email) {}
    public static final int MAX_NAME=200;
    public static final int MAX_NOTE=2000;
    public static CustomerDraft parse(Map<String,Object> body,boolean update) {
        if(update) Db.fields(body,"version","kind","name","phone","email","externalId","note","status","ownerId","contacts");
        else Db.fields(body,"kind","name","phone","email","externalId","note","ownerId","contacts","confirmDuplicate");
        String kind=text(body.get("kind"),16,false).toUpperCase(Locale.ROOT);
        if(!kind.equals("INDIVIDUAL")&&!kind.equals("ENTERPRISE")) throw ApiError.bad("INVALID_KIND","客户类型仅支持 INDIVIDUAL 或 ENTERPRISE");
        String name=text(body.get("name"),MAX_NAME,false);
        String phone=text(body.get("phone"),40,true);
        String email=email(body.get("email"));
        String externalId=text(body.get("externalId"),200,true);
        if(externalId.isEmpty()) externalId=null;
        String note=text(body.get("note"),MAX_NOTE,true);
        String status="ACTIVE";
        int version=0;
        if(update) {
            status=text(body.get("status"),16,true).toUpperCase(Locale.ROOT);
            if(status.isEmpty()) status="ACTIVE";
            if(!status.equals("ACTIVE")&&!status.equals("ARCHIVED")) throw ApiError.bad("INVALID_STATUS","客户状态仅支持 ACTIVE 或 ARCHIVED");
            Object raw=body.get("version");
            if(!(raw instanceof Integer)||(Integer)raw<1) throw ApiError.bad("INVALID_VERSION","version 必须为正整数");
            version=(Integer)raw;
        }
        String ownerId=text(body.get("ownerId"),128,true);
        List<Contact> contacts=body.containsKey("contacts") ? contacts(body.get("contacts"),kind,update) : null;
        return new CustomerDraft(kind,name,phone,email,externalId,note,status,version,
                ownerId.isEmpty()?null:ownerId,body.containsKey("ownerId"),contacts);
    }
    private static List<Contact> contacts(Object input,String kind,boolean update) {
        if(!(input instanceof List<?> list)||list.size()>30||(!kind.equals("ENTERPRISE")&&!list.isEmpty()))
            throw ApiError.bad("INVALID_CONTACTS","仅企业客户可维护联系人，最多30位");
        var ids=new HashSet<String>();
        var contacts=new ArrayList<Contact>();
        for(Object raw:list) {
            if(!(raw instanceof Map<?,?> contact)||!Set.of("id","name","role","phone","email").containsAll(contact.keySet()))
                throw ApiError.bad("INVALID_CONTACTS","联系人字段无效");
            String id=text(contact.get("id"),80,true);
            if(!id.isEmpty()&&(!update||!ids.add(id))) throw ApiError.bad("INVALID_CONTACTS","联系人标识无效或重复");
            contacts.add(new Contact(id,text(contact.get("name"),100,false),text(contact.get("role"),100,true),
                    text(contact.get("phone"),40,true),email(contact.get("email"))));
        }
        return List.copyOf(contacts);
    }
    private static String email(Object raw) {
        String email=text(raw,200,true);
        if(!email.isEmpty()&&!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) throw ApiError.bad("INVALID_EMAIL","邮箱格式无效");
        return email;
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
