package cn.workpanel.tools;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;

/** 真实 PostgreSQL，隔离 schema 覆盖发布历史、旧 AI 路径、拒绝和无损重复执行。 */
class AiWorkMigrationUpgradeTest {
    private final DriverManagerDataSource source = new DriverManagerDataSource(System.getenv("DB_URL"), System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
    private final JdbcTemplate jdbc = new JdbcTemplate(source);

    @Test void mainV15UpgradePreservesUsersLogsAndReplies() {
        String schema = schema();
        try {
            flyway(schema,"15").migrate();
            jdbc.update("INSERT INTO "+schema+".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('keep','default','keep','unchanged','13800000099','保留用户','EMPLOYEE','ACTIVE')");
            jdbc.update("INSERT INTO "+schema+".daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES ('log','default','keep',current_date,'{}'::jsonb,false,now())");
            jdbc.update("INSERT INTO "+schema+".log_comments(id,company_id,log_id,actor_id,text) VALUES ('comment','default','log','keep','原评论')");
            jdbc.update("INSERT INTO "+schema+".log_comments(id,company_id,log_id,actor_id,text,parent_id) VALUES ('reply','default','log','keep','原回复','comment')");
            var before = jdbc.queryForMap("SELECT password_hash FROM "+schema+".users WHERE id='keep'");
            flyway(schema,null).migrate();
            flyway(schema,null).validate();
            assertEquals(before,jdbc.queryForMap("SELECT password_hash FROM "+schema+".users WHERE id='keep'"));
            assertEquals("comment",jdbc.queryForObject("SELECT parent_id FROM "+schema+".log_comments WHERE id='reply'",String.class));
            assertEquals(flyway(schema,null).info().all().length,jdbc.queryForObject("SELECT count(*) FROM "+schema+".flyway_schema_history",Integer.class));
        } finally { drop(schema); }
    }

    @Test void knownV16V17V18AiHistoriesReconcileWithoutLosingBusinessOrInstallationMetadata() {
        for (int oldLast : List.of(16,17,18)) {
            String schema = schema();
            try {
                legacy(schema,oldLast);
                jdbc.update("INSERT INTO "+schema+".ai_work_items(id,company_id,owner_id,title) SELECT 'retained','default',id,'既有事项' FROM "+schema+".users LIMIT 1");
                var before = jdbc.queryForList("SELECT installed_rank,checksum,installed_by,installed_on,execution_time FROM "+schema+".flyway_schema_history ORDER BY installed_rank");
                AiWorkMigrationUpgrade.upgrade(source,schema);
                assertEquals(1,jdbc.queryForObject("SELECT count(*) FROM "+schema+".ai_work_items WHERE id='retained'",Integer.class));
                assertEquals(before,jdbc.queryForList("SELECT installed_rank,checksum,installed_by,installed_on,execution_time FROM "+schema+".flyway_schema_history WHERE installed_rank<=? ORDER BY installed_rank",oldLast));
                assertEquals(flyway(schema,null).info().all().length,jdbc.queryForObject("SELECT count(*) FROM "+schema+".flyway_schema_history",Integer.class));
                var history = jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank");
                AiWorkMigrationUpgrade.upgrade(source,schema);
                assertEquals(history,jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank"));
                flyway(schema,null).validate();
            } finally { drop(schema); }
        }
    }

    @Test void unknownIncompleteDuplicateFailedAndMissingSchemaHistoriesLeaveHistoryUntouched() {
        for (String mutation : List.of("UPDATE %s SET checksum=0 WHERE version='14'", "DELETE FROM %s WHERE version='2'",
            "UPDATE %s SET success=false WHERE version='15'", "UPDATE %s SET version='14' WHERE version='15'",
            "UPDATE %s SET script='unknown.sql' WHERE version='16'", "UPDATE %s SET description='unknown' WHERE version='16'",
            "UPDATE %s SET type='BASELINE' WHERE version='16'", "UPDATE %s SET version='19' WHERE version='16'")) {
            String schema = schema();
            try {
                legacy(schema,16);
                jdbc.update(mutation.formatted(schema+".flyway_schema_history"));
                var before = jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank");
                assertThrows(IllegalStateException.class,()->AiWorkMigrationUpgrade.upgrade(source,schema));
                assertEquals(before,jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank"));
            } finally { drop(schema); }
        }
        String schema = schema();
        try {
            legacy(schema,16);
            jdbc.execute("ALTER TABLE "+schema+".ai_work_items RENAME TO missing_ai_work_items");
            assertThrows(IllegalStateException.class,()->AiWorkMigrationUpgrade.upgrade(source,schema));
            assertEquals("V14__ai_work_assistant.sql",jdbc.queryForObject("SELECT script FROM "+schema+".flyway_schema_history WHERE version='14'",String.class));
        } finally { drop(schema); }
    }

    @Test void rejectsOriginalDatabaseAndUnsafeSchema() {
        assertThrows(IllegalArgumentException.class,()->AiWorkMigrationUpgrade.upgrade(source,"public"));
        assertThrows(IllegalArgumentException.class,()->AiWorkMigrationUpgrade.upgrade(source,"public; DROP SCHEMA public"));
        assertThrows(IllegalArgumentException.class,()->AiWorkMigrationUpgrade.main(new String[0]));
    }

    @Test void canonicalHistoryWithLaterMigrationsIsValidatedWithoutRewritingHistory() {
        String schema=schema();
        try {
            flyway(schema,null).migrate();
            var history=jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank");
            AiWorkMigrationUpgrade.upgrade(source,schema);
            assertEquals(history,jdbc.queryForList("SELECT * FROM "+schema+".flyway_schema_history ORDER BY installed_rank"));
        } finally { drop(schema); }
    }

    private void legacy(String schema,int last) {
        flyway(schema,"18").migrate();
        jdbc.update("INSERT INTO "+schema+".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('keep','default','keep','unchanged','13800000099','保留用户','EMPLOYEE','ACTIVE')");
        // 创建曾经实际部署的迁移顺序；SQL 与旧脚本完全相同。
        jdbc.update("UPDATE "+schema+".flyway_schema_history SET version=(version::int+1000)::text WHERE version::int>=14");
        Map<Integer,Integer> old = Map.of(14,17,15,18,16,14,17,15,18,16);
        for (var entry : old.entrySet()) {
            int canonical=entry.getKey(), legacy=entry.getValue();
            jdbc.update("UPDATE "+schema+".flyway_schema_history SET version=?,installed_rank=?,script=replace(script,?,?) WHERE version=?",String.valueOf(legacy),legacy+1000,"V"+canonical+"__","V"+legacy+"__",String.valueOf(canonical+1000));
        }
        jdbc.update("UPDATE "+schema+".flyway_schema_history SET installed_rank=installed_rank-1000 WHERE installed_rank>1000");
        if (last<18) {
            jdbc.execute("ALTER TABLE "+schema+".log_comments DROP COLUMN parent_id CASCADE");
            jdbc.execute("ALTER TABLE "+schema+".log_comments DROP CONSTRAINT log_comment_log_id_unique");
            jdbc.execute("DROP INDEX "+schema+".log_comments_log_time");
        }
        if (last<17) {
            jdbc.execute("ALTER TABLE "+schema+".daily_logs DROP CONSTRAINT daily_logs_submission_consistent");
            jdbc.execute("ALTER TABLE "+schema+".daily_logs ADD CONSTRAINT daily_logs_submission_consistent CHECK (submitted=(submitted_at IS NOT NULL))");
        }
        jdbc.update("DELETE FROM "+schema+".flyway_schema_history WHERE version::int>?",last);
    }

    private Flyway flyway(String schema,String version) {
        var configuration=Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema);
        if (version!=null) configuration.target(version);
        return configuration.load();
    }
    private String schema() {
        String schema = "ai_lineage_"+UUID.randomUUID().toString().replace("-","");
        // 模拟已存在的 public，避免 Flyway 自动创建 schema 的元记录进入业务迁移历史。
        jdbc.execute("CREATE SCHEMA "+schema);
        return schema;
    }
    private void drop(String schema) { jdbc.execute("DROP SCHEMA "+schema+" CASCADE"); }
}
