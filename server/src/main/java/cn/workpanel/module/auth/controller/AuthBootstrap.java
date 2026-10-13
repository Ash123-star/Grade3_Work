package cn.workpanel.module.auth.controller;

import cn.workpanel.*;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.beans.factory.annotation.Value;
import java.util.Map;

/** 启动时创建唯一初始管理员；不会覆盖已有管理员。 */
@Component
public class AuthBootstrap implements ApplicationRunner {
    final Db db; final BCryptPasswordEncoder passwords; final String account,password,phone;
    public AuthBootstrap(Db db,BCryptPasswordEncoder passwords,@Value("${app.admin-account}") String account,@Value("${app.admin-password}") String password,@Value("${app.admin-phone}") String phone) { this.db=db; this.passwords=passwords; this.account=account; this.password=password; this.phone=phone; }
    @Override @Transactional public void run(ApplicationArguments args) {
        db.one("SELECT id FROM companies WHERE id='default' FOR UPDATE");
        if(db.count("SELECT count(*) FROM users WHERE role='ADMIN'")>0) return;
        if(!account.matches("[a-zA-Z0-9_.-]{3,64}")||password.length()<12||password.getBytes(java.nio.charset.StandardCharsets.UTF_8).length>72||!phone.matches("1[3-9][0-9]{9}")) throw new IllegalStateException("首次启动需提供有效 ADMIN_ACCOUNT、至少 12 字符且不超过 72 字节的 ADMIN_PASSWORD 和 ADMIN_PHONE");
        if(db.count("SELECT count(*) FROM users WHERE account=? OR phone=?",account,phone)>0) throw new IllegalStateException("初始化账号已存在，不覆盖现有账号");
        String id=Db.id(); db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status,must_change_password,company_reviewer) VALUES (?,'default',?,?,?,'管理员','ADMIN','ACTIVE',true,true)",id,account,passwords.encode(password),phone);
        db.update("INSERT INTO user_roles VALUES (?,'ADMIN')",id); Actor a=Actor.from(db.one("SELECT * FROM users WHERE id=?",id)); db.audit(a,"INITIALIZED",id,Map.of(),Map.of("role","ADMIN"),"首次管理员初始化");
    }
}
