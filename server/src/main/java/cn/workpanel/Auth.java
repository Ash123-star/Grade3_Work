package cn.workpanel;

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
public class Auth {
    final Db db; final BCryptPasswordEncoder passwords; final Reviews reviews; final Limiter limiter; final int hours;
    Auth(Db db,BCryptPasswordEncoder passwords,Reviews reviews,Limiter limiter,@Value("${app.session-hours}") int hours) { this.db=db; this.passwords=passwords; this.reviews=reviews; this.limiter=limiter; this.hours=hours; }
    static String password(Map<String,Object> body,String key) { String p=Db.required(body,key); if(p.length()<12||p.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72) throw ApiError.bad("PASSWORD_POLICY","密码至少 12 个字符，UTF-8 编码不超过 72 字节"); return p; }
    @GetMapping("/departments") public List<Map<String,Object>> registrationDepartments() { return db.rows("SELECT id,name FROM departments WHERE company_id='default' ORDER BY id"); }
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
    @PostMapping("/login") @Transactional
    public Map<String,Object> login(@RequestBody Map<String,Object> b,HttpServletRequest r) {
        Db.fields(b,"account","password"); limiter.check("login:"+r.getRemoteAddr(),30,60);
        var rows=db.rows("SELECT * FROM users WHERE account=?",Db.required(b,"account"));
        if(rows.isEmpty()||!passwords.matches(Db.required(b,"password"),Db.str(rows.getFirst(),"password_hash"))||Db.str(rows.getFirst(),"status").equals("DISABLED")) throw new ApiError(401,"INVALID_CREDENTIALS","账号或密码错误");
        byte[] bytes=new byte[32]; new SecureRandom().nextBytes(bytes); String token=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Actor a=Actor.from(rows.getFirst()); db.update("INSERT INTO sessions VALUES (?,?,?)",Db.hash(token),a.id(),java.sql.Timestamp.from(Instant.now().plusSeconds(hours*3600L)));
        return Map.of("token",token,"expiresAt",Instant.now().plusSeconds(hours*3600L).toString(),"user",publicUser(rows.getFirst()));
    }
    @GetMapping("/me") public Map<String,Object> me(HttpServletRequest r) { return publicUser(db.one("SELECT * FROM users WHERE id=?",Actor.current(r).id())); }
    @PostMapping("/password") @Transactional
    public Map<String,Object> change(@RequestBody Map<String,Object> b,HttpServletRequest r) {
        Db.fields(b,"oldPassword","newPassword"); Actor a=Actor.current(r); var u=db.one("SELECT * FROM users WHERE id=? FOR UPDATE",a.id());
        if(!passwords.matches(Db.required(b,"oldPassword"),Db.str(u,"password_hash"))) throw new ApiError(401,"INVALID_CREDENTIALS","原密码错误");
        String p=password(b,"newPassword"); if(passwords.matches(p,Db.str(u,"password_hash"))) throw ApiError.bad("PASSWORD_UNCHANGED","新密码需与原密码不同");
        db.update("UPDATE users SET password_hash=?,must_change_password=false WHERE id=?",passwords.encode(p),a.id()); db.update("DELETE FROM sessions WHERE user_id=?",a.id());
        db.audit(a,"PASSWORD_CHANGED",a.id(),Map.of(),Map.of(),"用户改密并撤销所有会话"); return Map.of("reloginRequired",true);
    }
    @PostMapping("/logout") public Map<String,Object> logout(HttpServletRequest r) { db.update("DELETE FROM sessions WHERE token_hash=?",Db.hash(r.getHeader("Authorization").substring(7))); return Map.of("ok",true); }
    static Map<String,Object> publicUser(Map<String,Object> u) {
        var m=new LinkedHashMap<String,Object>(); for(String k:List.of("id","name","department_id","team_id","role","status","version","must_change_password","dispatch_enabled","company_reviewer")) m.put(k,u.get(k));
        return m;
    }
}

@Component
class Bootstrap implements ApplicationRunner {
    final Db db; final BCryptPasswordEncoder passwords; final String account,password,phone;
    Bootstrap(Db db,BCryptPasswordEncoder passwords,@Value("${app.admin-account}") String account,@Value("${app.admin-password}") String password,@Value("${app.admin-phone}") String phone) { this.db=db; this.passwords=passwords; this.account=account; this.password=password; this.phone=phone; }
    @Override @Transactional public void run(ApplicationArguments args) {
        db.one("SELECT id FROM companies WHERE id='default' FOR UPDATE");
        if(db.count("SELECT count(*) FROM users WHERE role='ADMIN'")>0) return;
        if(!account.matches("[a-zA-Z0-9_.-]{3,64}")||password.length()<12||password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72||!phone.matches("1[3-9][0-9]{9}")) throw new IllegalStateException("首次启动需提供有效 ADMIN_ACCOUNT、至少 12 字符且不超过 72 字节的 ADMIN_PASSWORD 和 ADMIN_PHONE");
        if(db.count("SELECT count(*) FROM users WHERE account=? OR phone=?",account,phone)>0) throw new IllegalStateException("初始化账号已存在，不覆盖现有账号");
        String id=Db.id(); db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status,must_change_password,company_reviewer) VALUES (?,'default',?,?,?,'管理员','ADMIN','ACTIVE',true,true)",id,account,passwords.encode(password),phone);
        db.update("INSERT INTO user_roles VALUES (?,'ADMIN')",id); Actor a=Actor.from(db.one("SELECT * FROM users WHERE id=?",id)); db.audit(a,"INITIALIZED",id,Map.of(),Map.of("role","ADMIN"),"首次管理员初始化");
    }
}
