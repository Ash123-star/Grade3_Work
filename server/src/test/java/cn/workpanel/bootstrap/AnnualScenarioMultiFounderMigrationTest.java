package cn.workpanel.bootstrap;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.Map;
import java.util.Arrays;
import java.util.UUID;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

/** 真实 PostgreSQL 场景迁移验收：多创始人仅扩展虚构年度数据，不修改审核规则。 */
class AnnualScenarioMultiFounderMigrationTest {
    private final DriverManagerDataSource source = new DriverManagerDataSource(
            System.getenv("DB_URL"), System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
    private final JdbcTemplate jdbc = new JdbcTemplate(source);

    @Test void annualScenarioAddsDistinctFoundersAndKeepsFounderExemptHistory() {
        String schema = "annual_founders_" + UUID.randomUUID().toString().replace("-", "");
        jdbc.execute("CREATE SCHEMA " + schema);
        try {
            migrateStructure(schema);
            annualScenario(schema).migrate();

            String s = schema + ".";
            assertEquals(4, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE company_id='annual-cm' AND role='FOUNDER' AND status='ACTIVE'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE id IN ('annual-founder-product','annual-founder-delivery')", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "user_roles WHERE user_id IN ('annual-founder-product','annual-founder-delivery') AND role_id='FOUNDER'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "task_participants WHERE task_id='annual-founder-collaboration-task'", Integer.class));
            assertEquals("FOUNDER_EXEMPT", jdbc.queryForObject("SELECT decision_source FROM " + s + "review_requests WHERE id='annual-founder-collaboration-task-review'", String.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='annual-founder-collaboration-task-review'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "task_labels WHERE creator_id IN ('annual-founder-product','annual-founder-delivery')", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_requests WHERE kind='TASK_RESCHEDULE' AND status IN ('PENDING','REJECTED')", Integer.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps rs JOIN " + s + "review_requests rr ON rr.id=rs.request_id WHERE rr.kind='TASK_RESCHEDULE' AND (rs.reviewer_id=rr.applicant_id OR NOT EXISTS (SELECT 1 FROM " + s + "reporting_relations r WHERE r.employee_id=rr.applicant_id AND r.manager_id=rs.reviewer_id))", Integer.class));
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "flyway_annual2026_history WHERE script='B1__annual_workplace.sql' AND success", Integer.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "flyway_annual2026_history WHERE version='0'", Integer.class));
            assertEquals(0, annualScenario(schema).migrate().migrationsExecuted);
        } finally {
            jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
        }
    }

    @Test void annualScenarioRejectsExistingFounderPrefixWithoutOverwritingData() {
        String schema = "annual_founder_conflict_" + UUID.randomUUID().toString().replace("-", "");
        jdbc.execute("CREATE SCHEMA " + schema);
        try {
            migrateStructure(schema);
            annualScenario(schema, "1").migrate();
            String s = schema + ".";
            jdbc.update("INSERT INTO " + s + "users(id,company_id,account,password_hash,name,role,status) VALUES ('annual-founder-product','annual-cm','unrelated-founder-product','not-a-password','既有数据','FOUNDER','ACTIVE')");

            assertThrows(FlywayException.class, () -> annualScenario(schema).migrate());
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE id='annual-founder-product' AND name='既有数据'", Integer.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE id='annual-founder-delivery'", Integer.class));
        } finally {
            jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
        }
    }

    @Test void annualScenarioRejectsNonScenarioBusinessDataWithoutChangingIt() {
        String schema = "annual_non_scenario_" + UUID.randomUUID().toString().replace("-", "");
        jdbc.execute("CREATE SCHEMA " + schema);
        try {
            migrateStructure(schema);
            String s = schema + ".";
            jdbc.update("INSERT INTO " + s + "companies(id,name) VALUES ('unrelated-company','既有业务公司')");

            assertThrows(FlywayException.class, () -> annualScenario(schema).migrate());
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "companies WHERE id='unrelated-company' AND name='既有业务公司'", Integer.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "companies WHERE id='annual-cm'", Integer.class));
        } finally {
            jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
        }
    }

    @Test void publishedV1AndV6HistoriesSkipNewBaselineAndPreserveUserChanges() {
        for (String version : new String[]{"1", "6"}) {
            String schema = "annual_legacy_" + UUID.randomUUID().toString().replace("-", "");
            jdbc.execute("CREATE SCHEMA " + schema);
            try {
                migrateStructure(schema);
                annualScenario(schema, version).migrate();
                String s = schema + ".";
                var v1 = Arrays.stream(annualScenario(schema).info().all())
                        .filter(info -> "V1__annual_workplace.sql".equals(info.getScript()))
                        .findFirst().orElseThrow();
                // 仅在隔离测试夹具中模拟已发布 V1 的真实脚本/校验和历史；
                // 生产入口绝不更改历史。业务数据已由 B1 建立，免受机器日期影响。
                jdbc.update("UPDATE " + s + "flyway_annual2026_history SET type='SQL', script=?, description=?, checksum=? WHERE script='B1__annual_workplace.sql'",
                        v1.getScript(), v1.getDescription(), v1.getChecksum());
                jdbc.update("UPDATE " + s + "users SET name='保留的人工修改' WHERE id='annual-founder'");
                var historyBefore = jdbc.queryForMap("SELECT script, checksum, installed_on FROM " + s + "flyway_annual2026_history WHERE version='1'");

                var migrated = annualScenario(schema);
                migrated.migrate();
                migrated.validate();
                assertEquals(historyBefore, jdbc.queryForMap("SELECT script, checksum, installed_on FROM " + s + "flyway_annual2026_history WHERE version='1'"));
                assertEquals("保留的人工修改", jdbc.queryForObject("SELECT name FROM " + s + "users WHERE id='annual-founder'", String.class));
                assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "flyway_annual2026_history WHERE script='B1__annual_workplace.sql'", Integer.class));
                assertEquals(0, annualScenario(schema).migrate().migrationsExecuted);
            } finally {
                jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
            }
        }
    }

    @Test void reportedBoundaryDatesKeepIndependentReviewers(@TempDir Path root) throws IOException {
        String baseline;
        try (var stream = getClass().getResourceAsStream("/db/scenario-annual2026/B1__annual_workplace.sql")) {
            assertNotNull(stream);
            baseline = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
        for (String day : new String[]{"2026-11-04", "2026-11-05", "2026-11-06"}) {
            String schema = "annual_date_" + UUID.randomUUID().toString().replace("-", "");
            var directory = Files.createDirectory(root.resolve(day));
            // 仅临时测试副本固定时钟；正式 B1 和已发布 V1 字节均不改动。
            Files.writeString(directory.resolve("B1__annual_workplace.sql"),
                    baseline.replace("now()", "timestamptz '" + day + " 12:00:00+08'"));
            jdbc.execute("CREATE SCHEMA " + schema);
            try {
                migrateStructure(schema);
                var configuration = Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema)
                        .locations("filesystem:" + directory.toAbsolutePath())
                        .table("flyway_annual2026_history")
                        .placeholders(Map.of("scenarioPasswordHash", "test-only-boundary-hash"));
                var scenario = ScenarioDataBootstrap.annualMigrations(configuration);
                scenario.migrate();
                String s = schema + ".";
                assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_requests WHERE kind='TASK_RESCHEDULE'", Integer.class), day);
                assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps rs JOIN " + s + "review_requests rr ON rr.id=rs.request_id JOIN " + s + "users a ON a.id=rr.applicant_id WHERE rr.kind='TASK_RESCHEDULE' AND (a.role='FOUNDER' OR rs.reviewer_id=rr.applicant_id OR NOT EXISTS (SELECT 1 FROM " + s + "reporting_relations r WHERE r.employee_id=rr.applicant_id AND r.manager_id=rs.reviewer_id))", Integer.class), day);
                assertEquals(0, scenario.migrate().migrationsExecuted, day);
            } finally {
                jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
            }
        }
    }

    private void migrateStructure(String schema) {
        Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load().migrate();
    }

    private Flyway annualScenario(String schema) {
        return annualScenario(schema, null);
    }

    private Flyway annualScenario(String schema, String target) {
        var configuration = Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema)
                .locations("classpath:db/scenario-annual2026").table("flyway_annual2026_history")
                .baselineOnMigrate(true).baselineVersion("0")
                .placeholders(Map.of("scenarioPasswordHash", "$2a$10$testScenarioPasswordHashPlaceholderValue12345678901234567890"));
        if (target != null) configuration.target(target);
        return ScenarioDataBootstrap.annualMigrations(configuration);
    }
}
