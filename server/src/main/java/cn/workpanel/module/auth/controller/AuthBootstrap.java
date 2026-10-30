package cn.workpanel.module.auth.controller;

import cn.workpanel.module.auth.application.DefaultAuthApplicationService;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Value;

/** 启动适配器：只调用初始化用例，不覆盖已有管理员。 */
@Component
@org.springframework.core.annotation.Order(0)
public class AuthBootstrap implements ApplicationRunner {
    private final DefaultAuthApplicationService service;
    private final String account, password, phone;
    public AuthBootstrap(DefaultAuthApplicationService service, @Value("${app.admin-account}") String account,
            @Value("${app.admin-password}") String password, @Value("${app.admin-phone}") String phone) {
        this.service = service; this.account = account; this.password = password; this.phone = phone;
    }
    @Override public void run(ApplicationArguments args) { service.initializeAdministrator(account, password, phone); }
}
