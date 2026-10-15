package cn.workpanel.tools;

import org.flywaydb.core.Flyway;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import javax.sql.DataSource;

/** 一次性旧 lyb 副本升级工具，不参与应用启动；原库必须先由外部脚本备份、恢复到新数据库。 */
public final class LegacyAuthUpgrade {
    private LegacyAuthUpgrade() {}

    public static void main(String[] args) {
        if(args.length!=1 || !args[0].equals("--restored-clone"))
            throw new IllegalArgumentException("Use the backup/restore script; --restored-clone required");
        var source = new DriverManagerDataSource(System.getenv("DB_URL"), System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
        upgrade(source, "public");
        System.out.println("Legacy clone upgraded and Flyway validation passed. Original database unchanged.");
    }

    /** 仅处理命名隔离的恢复副本（或测试 schema），未知脚本/校验和拒绝转换；失败副本保留供检查。 */
    public static void upgrade(DataSource source, String schema) {
        if(!schema.equals("public") && !schema.matches("legacy_upgrade_[a-f0-9]{32}"))
            throw new IllegalArgumentException("Invalid isolated schema");
        var jdbc=new JdbcTemplate(source);
        String database=jdbc.queryForObject("SELECT current_database()",String.class);
        if(schema.equals("public") && (database==null || !database.matches("workpanel_lyb_upgrade_[a-f0-9]{12}")))
            throw new IllegalArgumentException("Refusing original database; restore to a new workpanel_lyb_upgrade_<12 hex> database first");
        String history=schema+".flyway_schema_history";
        new TransactionTemplate(new DataSourceTransactionManager(source)).executeWithoutResult(tx -> {
            var rows=jdbc.queryForList("SELECT version,script,checksum,success FROM "+history+" WHERE version IN ('5','10','11','12','13') FOR UPDATE");
            var auth=rows.stream().filter(r -> ("V5__auth_login_protection.sql".equals(r.get("script")) || "V10__auth_login_protection.sql".equals(r.get("script")) || "V12__auth_login_protection.sql".equals(r.get("script")))).toList();
            if(auth.size()!=1 || !Integer.valueOf(-1773296244).equals(auth.getFirst().get("checksum")) || !Boolean.TRUE.equals(auth.getFirst().get("success")))
                throw new IllegalStateException("Unknown legacy auth migration; no conversion performed");
            if(rows.stream().anyMatch(r -> "13".equals(r.get("version"))))
                throw new IllegalStateException("V13 already exists; refuse ambiguous history");
            // 同一个已执行脚本只移动版本号；保留校验和、执行人、时间与已有登录防护数据。
            jdbc.update("UPDATE "+history+" SET version='13',script='V13__auth_login_protection.sql' WHERE script=?",auth.getFirst().get("script"));
            for(var row:rows) if("V11__task_review_kinds.sql".equals(row.get("script"))) {
                if(!Integer.valueOf(-1563727389).equals(row.get("checksum")) || !Boolean.TRUE.equals(row.get("success")))
                    throw new IllegalStateException("Unknown legacy task review constraint migration");
                // main V10 重新建立同一约束且增加 MEMORY；旧约束本身不删除任何业务数据。
                jdbc.update("DELETE FROM "+history+" WHERE version='11' AND script='V11__task_review_kinds.sql'");
            }
        });
        Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).outOfOrder(true).load().migrate();
        // 最终恢复普通启动配置并验证，不要求生产环境长期启用 outOfOrder。
        Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load().validate();
    }
}
