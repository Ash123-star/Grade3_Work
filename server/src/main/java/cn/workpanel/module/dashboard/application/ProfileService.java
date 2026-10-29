package cn.workpanel.module.dashboard.application;

import cn.workpanel.*;
import cn.workpanel.module.auth.application.DefaultAuthApplicationService;
import cn.workpanel.module.dashboard.infrastructure.ProfileRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;
import java.util.regex.Pattern;

/** 本人版本化资料维护与组织上级读取；结构化列优先于旧 JSONB 展示值。 */
@Service
public class ProfileService {
    private final ProfileRepository repository;
    public ProfileService(ProfileRepository repository) { this.repository=repository; }
    public Map<String,Object> get(Actor actor,String id) {
        var user=repository.user(actor,id,false);
        if(!actor.id().equals(id)&&!actor.global()&&!repository.ancestor(actor,id)) throw ApiError.forbidden();
        var result=new LinkedHashMap<>(DefaultAuthApplicationService.publicUser(user));
        for(String field:List.of("phone","email","gender","age")) result.put(field,user.get(field));
        result.put("employmentStartDate",user.get("employment_start_date"));
        result.put("profile",repository.json(user.get("profile"))); result.put("viewingSelf",actor.id().equals(id));
        result.put("department",repository.unit("departments",actor.company(),user.get("department_id")));
        result.put("team",repository.unit("teams",actor.company(),user.get("team_id"))); return result;
    }
    @Transactional
    public Map<String,Object> update(Actor actor,Map<String,Object> body) {
        if(!actor.status().equals("ACTIVE")||actor.mustChange()) throw ApiError.forbidden();
        Db.fields(body,"avatarAttachmentId","introduction","phone","email","gender","age","version");
        int expected=Db.version(body); var user=repository.user(actor,actor.id(),true);
        if(!"ACTIVE".equals(user.get("status"))||Boolean.TRUE.equals(user.get("must_change_password"))) throw ApiError.forbidden();
        if(((Number)user.get("version")).intValue()!=expected) throw ApiError.conflict();
        String phone=string(user.get("phone")),email=string(user.get("email")),gender=string(user.get("gender")); Object age=user.get("age");
        if(body.containsKey("phone")) {
            phone=nullableText(body,"phone",32);
            if(phone!=null&&!phone.matches("1[3-9][0-9]{9}")) throw ApiError.bad("INVALID_PHONE","手机号格式无效");
            repository.lockPhone(phone);
            if(phone!=null&&repository.phoneTaken(phone,actor.id())) throw new ApiError(409,"PHONE_CONFLICT","手机号已被使用");
        }
        if(body.containsKey("email")) {
            email=nullableText(body,"email",320);
            if(email!=null&&!Pattern.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$",email)) throw ApiError.bad("INVALID_EMAIL","邮箱格式无效");
        }
        if(body.containsKey("gender")) gender=nullableText(body,"gender",32);
        if(body.containsKey("age")) {
            age=body.get("age");
            if(age!=null&&(!(age instanceof Number number)||!Double.isFinite(number.doubleValue())||number.doubleValue()!=number.intValue()||number.intValue()<0)) throw ApiError.bad("INVALID_AGE","年龄必须为非负整数或空值");
            if(age instanceof Number number) age=number.intValue();
        }
        var profile=repository.json(user.get("profile"));
        if(body.containsKey("introduction")) profile.put("introduction",nullableText(body,"introduction",20000));
        if(body.containsKey("avatarAttachmentId")) {
            String avatar=nullableText(body,"avatarAttachmentId",200);
            if(avatar!=null) repository.requireOwnAvatar(actor,avatar);
            profile.put("avatarAttachmentId",avatar);
        }
        // 只有本人明确改写该字段时才清除旧重复值；其他历史/非法数据由迁移保留。
        for(String field:List.of("phone","email","gender","age")) if(body.containsKey(field)) profile.remove(field);
        repository.update(actor,expected,phone,email,gender,age,profile); return get(actor,actor.id());
    }
    private static String string(Object value) { return value==null?null:value.toString(); }
    private static String nullableText(Map<String,Object> body,String key,int max) {
        Object value=body.get(key); if(value==null) return null;
        if(!(value instanceof String text)) throw ApiError.bad("INVALID_FIELD",key+" 必须为文本或空值");
        String trimmed=text.trim(); if(trimmed.length()>max) throw ApiError.bad("INVALID_FIELD",key+" 长度超限"); return trimmed.isEmpty()?null:trimmed;
    }
}
