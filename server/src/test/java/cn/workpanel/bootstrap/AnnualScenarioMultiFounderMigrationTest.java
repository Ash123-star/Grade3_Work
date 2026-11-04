package cn.workpanel.bootstrap;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.Map;
import java.util.UUID;

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
            assertEquals(3, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE company_id='annual-cm' AND role='FOUNDER' AND status='ACTIVE'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE id IN ('annual-founder-product','annual-founder-delivery')", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "user_roles WHERE user_id IN ('annual-founder-product','annual-founder-delivery') AND role_id='FOUNDER'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "task_participants WHERE task_id='annual-founder-collaboration-task'", Integer.class));
            assertEquals("FOUNDER_EXEMPT", jdbc.queryForObject("SELECT decision_source FROM " + s + "review_requests WHERE id='annual-founder-collaboration-task-review'", String.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='annual-founder-collaboration-task-review'", Integer.class));
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "task_labels WHERE creator_id IN ('annual-founder-product','annual-founder-delivery')", Integer.class));
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
        return configuration.load();
    }
}
