package cn.workpanel.bootstrap;

import org.flywaydb.core.Flyway;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * 显式启用的虚构场景初始化；正式Flyway完成后运行，使用独立历史表，不改变正式迁移版本。
 * 仅由部署人员通过 SCENARIO_DATA_ENABLED=true 启用，无HTTP入口；密码须从环境传入，禁止写日志。
 * SQL冲突使本次种子事务回滚；同一版本重启由Flyway跳过，不重置账号密码或业务数据。
 */
@Component
@ConditionalOnProperty(name = "app.scenario-data-enabled", havingValue = "true")
public class ScenarioDataBootstrap implements ApplicationRunner {
    private final DataSource dataSource;
    private final BCryptPasswordEncoder passwords;
    private final String password;
    private final String dataset;

    public ScenarioDataBootstrap(DataSource dataSource, BCryptPasswordEncoder passwords,
            @Value("${app.scenario-password:}") String password,
            @Value("${app.scenario-dataset:legacy}") String dataset) {
        this.dataSource = dataSource;
        this.passwords = passwords;
        this.password = password;
        this.dataset = dataset;
    }

    static void requirePassword(String password) {
        if (password == null || password.isBlank() || password.length() < 6
                || password.getBytes(StandardCharsets.UTF_8).length > 72) {
            throw new IllegalArgumentException("启用场景初始化必须提供至少6字符且UTF-8不超过72字节的SCENARIO_PASSWORD（仅测试账号）");
        }
    }

    @Override
    public void run(ApplicationArguments args) {
        requirePassword(password);
        if (!dataset.equals("legacy") && !dataset.equals("annual-2026"))
            throw new IllegalArgumentException("SCENARIO_DATASET仅支持legacy或annual-2026");
        boolean annual = dataset.equals("annual-2026");
        if (annual && password.length() < 12)
            throw new IllegalArgumentException("annual-2026测试密码至少12字符，满足现有前后端校验");
        Flyway.configure().dataSource(dataSource)
                .locations(annual ? "classpath:db/scenario-annual2026" : "classpath:db/scenario")
                .table(annual ? "flyway_annual2026_history" : "flyway_scenario_history")
                .baselineOnMigrate(true).baselineVersion("0")
                .placeholders(Map.of("scenarioPasswordHash", passwords.encode(password)))
                .load().migrate();
    }
}
