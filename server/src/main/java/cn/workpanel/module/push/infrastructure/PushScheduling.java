package cn.workpanel.module.push.infrastructure;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

/** Keep provider timeouts off the scheduler that delivers station messages and deadline events. */
@Configuration
public class PushScheduling {
    @Bean(name="taskScheduler")
    ThreadPoolTaskScheduler businessScheduler() { return scheduler("business-jobs-"); }
    @Bean(name="pushDeliveryScheduler")
    ThreadPoolTaskScheduler pushDeliveryScheduler() { return scheduler("push-delivery-"); }
    private ThreadPoolTaskScheduler scheduler(String prefix) {
        var scheduler=new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(1);scheduler.setThreadNamePrefix(prefix);
        scheduler.setRemoveOnCancelPolicy(true);
        return scheduler;
    }
}
