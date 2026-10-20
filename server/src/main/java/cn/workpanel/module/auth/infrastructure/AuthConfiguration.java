package cn.workpanel.module.auth.infrastructure;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 模块时钟可在测试中替换，不更改公共安全配置。 */
@Configuration
public class AuthConfiguration {
    @Bean("authClock") public Clock authClock() { return Clock.systemUTC(); }
}
