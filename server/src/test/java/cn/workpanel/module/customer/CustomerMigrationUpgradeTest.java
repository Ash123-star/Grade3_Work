package cn.workpanel.module.customer;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.FlywayException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

class CustomerMigrationUpgradeTest {
    private final String schema="customer_upgrade_"+UUID.randomUUID().toString().replace("-","");
    private final DriverManagerDataSource source=new DriverManagerDataSource(
        System.getenv("DB_URL"),System.getenv("DB_USER"),System.getenv("DB_PASSWORD"));
    private final JdbcTemplate sql=new JdbcTemplate(source);

    private Flyway flyway(String target) {
        return Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).target(target).load();
    }

    @AfterEach void dropTestSchema() {
        sql.execute("DROP SCHEMA IF EXISTS "+schema+" CASCADE");
    }

    @Test void upgradesV36WithoutChangingExistingRowsAndEnforcesReceiptOwnership() {
        flyway("36").migrate();
        sql.update("INSERT INTO "+schema+".companies(id,name) VALUES ('other','Keep Company')");
        var before=sql.queryForList("SELECT * FROM "+schema+".companies ORDER BY id");

        var upgrade=flyway("38");
        assertEquals(2,upgrade.migrate().migrationsExecuted);
        upgrade.validate();
        assertEquals(0,upgrade.migrate().migrationsExecuted);
        assertEquals(before,sql.queryForList("SELECT * FROM "+schema+".companies ORDER BY id"));

        seedCustomersAndBenefit();
        String insert="INSERT INTO "+schema+".customer_benefit_redemptions"+
            "(id,company_id,benefit_id,customer_id,event_key,used_at_redemption,remaining_at_redemption)"+
            " VALUES (?,?,'benefit',?,?,1,0)";
        assertEquals(1,sql.update(insert,"first","default","owner","same"));
        assertThrows(DataIntegrityViolationException.class,()->sql.update(insert,"duplicate","default","owner","same"));
        assertOwnershipViolation(()->sql.update(insert,"wrong-customer","default","different","different"));
        assertOwnershipViolation(()->sql.update(insert,"wrong-company","other","other-customer","different"));
        assertEquals(1,sql.queryForObject("SELECT count(*) FROM "+schema+".customer_benefit_redemptions",Integer.class));
    }

    @Test void preservesLegacyRedemptionsWhenExactCountersCannotBeRecovered() {
        flyway("37").migrate();
        sql.update("INSERT INTO "+schema+".companies(id,name) VALUES ('other','Other Company')");
        seedCustomersAndBenefit();
        String table=schema+".customer_benefit_redemptions";
        sql.update("INSERT INTO "+table+"(id,company_id,benefit_id,customer_id,event_key)"+
            " VALUES ('legacy','default','benefit','owner','legacy-key')");
        var before=sql.queryForList("SELECT * FROM "+table);

        var failure=assertThrows(FlywayException.class,()->flyway("38").migrate());
        assertTrue(failure.getMessage().contains("cannot recover exact receipt counters"),failure.getMessage());
        assertEquals(before,sql.queryForList("SELECT * FROM "+table));
    }

    @Test void upgradesExistingCustomersWithoutInventingOwnersOrContacts() {
        flyway("41").migrate();
        sql.update("INSERT INTO "+schema+".companies(id,name) VALUES ('other','Other Company')");
        seedCustomersAndBenefit();

        var upgrade=flyway("45");
        assertEquals(2,upgrade.migrate().migrationsExecuted);
        upgrade.validate();
        assertEquals(0,upgrade.migrate().migrationsExecuted);
        var profile=sql.queryForMap("SELECT name,owner_id,contacts::text FROM "+schema+".customers WHERE id='owner'");
        assertEquals("Owner",profile.get("name"));
        assertNull(profile.get("owner_id"));
        assertEquals("[]",profile.get("contacts"));
        assertThrows(DataIntegrityViolationException.class,()->sql.update(
            "UPDATE "+schema+".customers SET contacts='[{\"name\":\"Contact\"}]' WHERE id='owner'"));
        assertEquals(1,sql.queryForObject("SELECT count(*) FROM "+schema+".customer_benefits WHERE id='benefit'",Integer.class));
    }

    private void seedCustomersAndBenefit() {
        sql.update("INSERT INTO "+schema+".customers(id,company_id,kind,name) VALUES"+
            " ('owner','default','INDIVIDUAL','Owner'), ('different','default','INDIVIDUAL','Different'),"+
            " ('other-customer','other','INDIVIDUAL','Other')");
        sql.update("INSERT INTO "+schema+".customer_benefits(id,company_id,customer_id,kind,name,valid_from,valid_to)"+
            " VALUES ('benefit','default','owner','ANNUAL_CARD','Annual pass',CURRENT_DATE,CURRENT_DATE)");
    }

    private static void assertOwnershipViolation(Runnable insert) {
        var failure=assertThrows(DataIntegrityViolationException.class,insert::run);
        assertTrue(failure.getMostSpecificCause().getMessage().contains("customer_redemptions_benefit_owner_fk"));
    }
}
