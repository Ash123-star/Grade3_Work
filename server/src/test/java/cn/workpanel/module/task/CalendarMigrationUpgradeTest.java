package cn.workpanel.module.task;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.dao.DataIntegrityViolationException;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

/** Real PostgreSQL; each test owns only its randomly named temporary schema. */
class CalendarMigrationUpgradeTest {
    final DriverManagerDataSource source=new DriverManagerDataSource(System.getenv("DB_URL"),System.getenv("DB_USER"),System.getenv("DB_PASSWORD"));
    final JdbcTemplate jdbc=new JdbcTemplate(source);
    Flyway flyway(String schema,String target) {
        var c=Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema);
        if(target!=null)c.target(target);
        return c.load();
    }
    @Test void emptyAndV21DatabasesMigrateWithoutChangingExistingTask() {
        for(boolean existing:new boolean[]{false,true}) {
            String schema="calendar_upgrade_"+UUID.randomUUID().toString().replace("-","");
            jdbc.execute("CREATE SCHEMA "+schema);
            var scopedSource=new DriverManagerDataSource(System.getenv("DB_URL")+(System.getenv("DB_URL").contains("?")?"&":"?")+"currentSchema="+schema,System.getenv("DB_USER"),System.getenv("DB_PASSWORD"));
            var jdbc=new JdbcTemplate(scopedSource);
            try {
                if(existing) {
                    flyway(schema,"21").migrate();
                    jdbc.update("INSERT INTO "+schema+".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('keep','default','keep','unchanged','keep','Keep','LEADER','ACTIVE')");
                    jdbc.update("INSERT INTO "+schema+".tasks(id,company_id,owner_id,issuer_id,title,deadline,body,version) VALUES ('keep-task','default','keep','keep','Keep task','2026-11-30T18:00:00+08:00','{}',3)");
                }
                var before=existing?jdbc.queryForList("SELECT * FROM "+schema+".tasks"):java.util.List.of();
                flyway(schema,null).migrate();flyway(schema,null).validate();
                assertEquals(before,jdbc.queryForList("SELECT * FROM "+schema+".tasks"));
                assertEquals(0,flyway(schema,null).migrate().migrationsExecuted);
                assertEquals(0,jdbc.queryForObject("SELECT count(*) FROM "+schema+".task_reschedule_commands",Integer.class));
                if(existing) {
                    jdbc.update("INSERT INTO "+schema+".review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES ('review','default','keep','TASK_RESCHEDULE','keep-task',3,'{}','{}','Keep')");
                    String insert="INSERT INTO "+schema+".task_reschedule_commands(company_id,actor_id,idempotency_key,task_id,review_id,request_hash,hash_version) VALUES (?,?,?,?,?,'hash',1)";
                    jdbc.update(insert,"default","keep","k".repeat(128),"keep-task","review");
                    assertThrows(DataIntegrityViolationException.class,()->jdbc.update(insert,"default","keep","k".repeat(128),"keep-task","review"));
                    assertThrows(DataIntegrityViolationException.class,()->jdbc.update(insert,"other-company","keep","other-key","keep-task","review"));
                    assertThrows(DataIntegrityViolationException.class,()->jdbc.update(insert,"default","keep","k".repeat(129),"keep-task","review"));
                }
            } finally { jdbc.execute("DROP SCHEMA "+schema+" CASCADE"); }
        }
    }
}
