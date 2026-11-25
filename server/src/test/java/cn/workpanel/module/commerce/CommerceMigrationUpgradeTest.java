package cn.workpanel.module.commerce;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.Arrays;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

class CommerceMigrationUpgradeTest {
    @Test
    void upgradesExistingV36CompanyThroughCustomerAndCommerceMigrations() {
        String url = System.getenv("DB_URL");
        assertNotNull(url, "Use scripts/test-backend.ps1 for an isolated PostgreSQL");
        var source = new DriverManagerDataSource(url, System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
        var jdbc = new JdbcTemplate(source);
        String schema = "commerce_upgrade_" + UUID.randomUUID().toString().replace("-", "");
        try {
            Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).target("36").load().migrate();
            jdbc.update("INSERT INTO " + schema + ".companies(id,name) VALUES ('existing-company','Existing')");
            jdbc.update("INSERT INTO " + schema + ".users(id,company_id,account,password_hash,name,phone,role,status)"
                    + " VALUES ('existing-admin','existing-company','existing','sample','Existing','test-1','ADMIN','ACTIVE')");

            var latest = Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load();
            latest.migrate();
            latest.validate();
            assertTrue(Arrays.stream(latest.info().applied())
                    .anyMatch(info -> info.getVersion() != null && "39".equals(info.getVersion().getVersion())));
            assertEquals("Existing", jdbc.queryForObject("SELECT name FROM " + schema
                    + ".companies WHERE id='existing-company'", String.class));
            jdbc.update("INSERT INTO " + schema + ".commerce_imports(company_id,id,sha256,actor_id) VALUES (?,?,?,?)",
                    "existing-company", "import-1", "a".repeat(64), "existing-admin");
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class, () ->
                    jdbc.update("INSERT INTO " + schema + ".commerce_imports(company_id,id,sha256,actor_id) VALUES (?,?,?,?)",
                            "existing-company", "import-2", "a".repeat(64), "existing-admin"));
        } finally {
            jdbc.execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
        }
    }
}
