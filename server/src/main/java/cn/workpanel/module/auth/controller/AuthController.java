package cn.workpanel.module.auth.controller;

import cn.workpanel.*;
import cn.workpanel.module.review.application.ReviewApplicationService;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.*;

@RestController
@RequestMapping("/api/auth")
/** 认证接口：公开注册/登录与已登录用户的会话和密码管理。所有写操作返回统一错误体并带 traceId。 */
public class AuthController {
    final Db db; final BCryptPasswordEncoder passwords; final ReviewApplicationService reviews; final Limiter limiter; final int hours;
    public AuthController(Db db,BCryptPasswordEncoder passwords,ReviewApplicationService reviews,Limiter limiter,@Value("${app.session-hours}") int hours) { this.db=db; this.passwords=passwords; this.reviews=reviews; this.limiter=limiter; this.hours=hours; }
    static String password(Map<String,Object> body,String key) { String p=Db.required(body,key); if(p.length()<12||p.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72) throw ApiError.bad("PASSWORD_POLICY","密码至少 12 个字符，UTF-8 编码不超过 72 字节"); return p; }
    /** 获取注册可选部门。公开接口；失败返回 5xx；不接受写入参数。 */
    @GetMapping("/departments") public List<Map<String,Object>> registrationDepartments() { return db.rows("SELECT id,name FROM departments WHERE company_id='default' ORDER BY id"); }
    /** 注册待确认员工。请求含 account、password、phone、name、departmentId；禁止 role；重复账号返回 409。 */
    @PostMapping("/register") @Transactional
    public Map<String,Object> register(@RequestBody Map<String,Object> b,HttpServletRequest r) {
        limiter.check("register:"+r.getRemoteAddr(),10,3600); Db.fields(b,"account","password","phone","name","departmentId");
        String account=Db.required(b,"account"),phone=Db.required(b,"phone");
        if(!account.matches("[a-zA-Z0-9_.-]{3,64}")||!phone.matches("1[3-9][0-9]{9}")) throw ApiError.bad("INVALID_ACCOUNT","账号或手机号无效");
        String dept=Db.required(b,"departmentId"); db.one("SELECT id FROM departments WHERE id=? AND company_id='default'",dept);
        String id=Db.id(); db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,role,status) VALUES (?,'default',?,?,?,?,?,'EMPLOYEE','PENDING')",id,account,passwords.encode(password(b,"password")),phone,Db.required(b,"name"),dept);
        db.update("INSERT INTO user_roles VALUES (?,'EMPLOYEE')",id);
        Actor a=Actor.from(db.one("SELECT * FROM users WHERE id=?",id));
        var review=reviews.create(a,"MEMBERSHIP",id,1,Map.of("status","PENDING"),Map.of("status","ACTIVE","departmentId",dept),"注册部门归属申请");
        return Map.of("id",id,"role","EMPLOYEE","status","PENDING","reviewId",review.get("id"),"phoneVerified",false);
    }
    /** 登录并创建会话。请求含 account、password；成功返回 Bearer token；凭据错误 401，限流 429。 */
    @PostMapping("/login") @Transactional
    public Map<String,Object> login(@RequestBody Map<String,Object> b,HttpServletRequest r) {
        Db.fields(b,"account","password"); limiter.check("login:"+r.getRemoteAddr(),30,60);
        var rows=db.rows("SELECT * FROM users WHERE account=?",Db.required(b,"account"));
        if(rows.isEmpty()||!passwords.matches(Db.required(b,"password"),Db.str(rows.getFirst(),"password_hash"))||Db.str(rows.getFirst(),"status").equals("DISABLED")) throw new ApiError(401,"INVALID_CREDENTIALS","账号或密码错误");
        byte[] bytes=new byte[32]; new SecureRandom().nextBytes(bytes); String token=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Actor a=Actor.from(rows.getFirst()); db.update("INSERT INTO sessions VALUES (?,?,?)",Db.hash(token),a.id(),java.sql.Timestamp.from(Instant.now().plusSeconds(hours*3600L)));
        return Map.of("token",token,"expiresAt",Instant.now().plusSeconds(hours*3600L).toString(),"user",publicUser(rows.getFirst()));
    }
    /** 获取当前用户公开资料。需要有效会话；不返回密码、手机号或私人备注。 */
    @GetMapping("/me") public Map<String,Object> me(HttpServletRequest r) { return publicUser(db.one("SELECT * FROM users WHERE id=?",Actor.current(r).id())); }
    /** 修改密码并撤销旧会话。请求含 oldPassword、newPassword；首次改密也使用本接口；版本不适用。 */
    @PostMapping("/password") @Transactional
    public Map<String,Object> change(@RequestBody Map<String,Object> b,HttpServletRequest r) {
        Db.fields(b,"oldPassword","newPassword"); Actor a=Actor.current(r); var u=db.one("SELECT * FROM users WHERE id=? FOR UPDATE",a.id());
        if(!passwords.matches(Db.required(b,"oldPassword"),Db.str(u,"password_hash"))) throw new ApiError(401,"INVALID_CREDENTIALS","原密码错误");
        String p=password(b,"newPassword"); if(passwords.matches(p,Db.str(u,"password_hash"))) throw ApiError.bad("PASSWORD_UNCHANGED","新密码需与原密码不同");
        db.update("UPDATE users SET password_hash=?,must_change_password=false WHERE id=?",passwords.encode(p),a.id()); db.update("DELETE FROM sessions WHERE user_id=?",a.id());
        db.audit(a,"PASSWORD_CHANGED",a.id(),Map.of(),Map.of(),"用户改密并撤销所有会话"); return Map.of("reloginRequired",true);
    }
    /** 撤销当前 Bearer 会话。需要有效会话；重复调用返回会话错误或成功取决于过滤器状态。 */
    @PostMapping("/logout") public Map<String,Object> logout(HttpServletRequest r) { db.update("DELETE FROM sessions WHERE token_hash=?",Db.hash(r.getHeader("Authorization").substring(7))); return Map.of("ok",true); }
    public static Map<String,Object> publicUser(Map<String,Object> u) {
        var m=new LinkedHashMap<String,Object>(); for(String k:List.of("id","name","department_id","team_id","role","status","version","must_change_password","dispatch_enabled","company_reviewer")) m.put(k,u.get(k));
        return m;
    }
}

