package cn.workpanel.tools;

import org.flywaydb.core.Flyway;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.support.TransactionTemplate;

import javax.sql.DataSource;
import java.util.*;

/**
 * 一次性未发布 AI 历史协调，不参与应用启动，不执行 repair。
 * 仅恢复副本/隔离测试 schema 可调用；凭据从环境读取，输出只含升级状态。
 * 前置：外部备份并恢复，禁止业务连接副本；失败副本不得接入 API。
 */
public final class AiWorkMigrationUpgrade {
    private AiWorkMigrationUpgrade() {}

    private record Migration(String name, int checksum) {
        String script(int version) { return "V" + version + "__" + name + ".sql"; }
        String description() { return name.replace('_', ' '); }
    }

    // 2026-10-22 已知且未发布的本地历史。未知或未来历史必须另行审阅，不能泛化 repair。
    private static final List<Migration> LEGACY = List.of(
        new Migration("collaboration", -152661232), new Migration("tenant_constraints", 2068391238),
        new Migration("review_policy", 2057537554), new Migration("business_integrity", 1416035206),
        new Migration("task_dispatch", 956123190), new Migration("task_lifecycle", 64462514),
        new Migration("task_list_query_index", 980252150), new Migration("daily_log_query_index", -635187176),
        new Migration("log_task_linkage_index", 53215119), new Migration("memory_knowledge", 1295019192),
        new Migration("knowledge_rebuild", -526290678), new Migration("task_revision_review_kinds", 704295839),
        new Migration("auth_login_protection", -1773296244), new Migration("ai_work_assistant", -1938751824),
        new Migration("durable_delivery_checks", 1271806828), new Migration("ai_authorization_policy", 633458384),
        new Migration("log_first_submission_window", 418086942), new Migration("log_comment_replies", 1370999752)
    );
    private static final Map<Integer, Integer> VERSIONS = Map.of(14,16,15,17,16,18,17,14,18,15);

    public static void main(String[] args) {
        if (!Arrays.equals(args, new String[]{"--restored-clone"}))
            throw new IllegalArgumentException("Restore a backup first; --restored-clone required");
        var source = new DriverManagerDataSource(System.getenv("DB_URL"), System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
        upgrade(source, "public");
        System.out.println("AI migration clone upgraded; ordinary Flyway validation passed. Original database unchanged.");
    }

    /** 校验完整白名单后，仅更改恢复副本的版本与脚本名；保留安装顺序、校验和、人和时间。 */
    public static void upgrade(DataSource source, String schema) {
        if (!schema.equals("public") && !schema.matches("ai_lineage_[a-f0-9]{32}"))
            throw new IllegalArgumentException("Invalid isolated schema");
        var jdbc = new JdbcTemplate(source);
        String database = jdbc.queryForObject("SELECT current_database()", String.class);
        if (schema.equals("public") && (database == null || !database.matches("workpanel_ai_upgrade_[a-f0-9]{12}")))
            throw new IllegalArgumentException("Refusing original database; restore to workpanel_ai_upgrade_<12 hex> first");
        String history = schema + ".flyway_schema_history";
        new TransactionTemplate(new DataSourceTransactionManager(source)).executeWithoutResult(tx -> {
            jdbc.execute("SET LOCAL lock_timeout='5s'");
            jdbc.execute("LOCK TABLE " + history + " IN ACCESS EXCLUSIVE MODE");
            if (schema.equals("public") && jdbc.queryForObject("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid()", Long.class) != 0)
                throw new IllegalStateException("Clone has other connections; no conversion performed");
            var rows = jdbc.queryForList("SELECT version,description,type,script,checksum,success FROM " + history + " ORDER BY installed_rank");
            if (matches(rows.stream().filter(row -> row.get("version") instanceof String v && v.matches("[1-9][0-9]?") && Integer.parseInt(v)<=18).toList(), canonical())) return; // 已协调副本可重复验证，不重排历史。
            if (rows.size() < 16 || rows.size() > 18 || !matches(rows, LEGACY.subList(0, rows.size())))
                throw new IllegalStateException("Unknown, incomplete or failed AI history; no conversion performed");
            // 校验关键结构，避免把只伪造了历史、未真正执行的脚本当成升级成功。
            for (String table : List.of("ai_work_items", "ai_action_receipts", "task_delivery_check_jobs", "ai_work_authorizations"))
                if (jdbc.queryForObject("SELECT to_regclass(?) IS NOT NULL", Boolean.class, schema + "." + table) != Boolean.TRUE)
                    throw new IllegalStateException("AI schema missing; no conversion performed");
            if (jdbc.queryForObject("SELECT count(*) FROM information_schema.columns WHERE table_schema=? AND table_name='companies' AND column_name='ai_authorization_revision'", Long.class, schema) != 1)
                throw new IllegalStateException("Authorization schema missing; no conversion performed");
            // 先暂存不重叠版本，避免版本唯一性中途碰撞；事务失败自动恢复。
            jdbc.update("UPDATE " + history + " SET version=(version::int+1000)::text WHERE version::int>=14");
            for (int old = 14; old <= rows.size(); old++) {
                int version = VERSIONS.get(old);
                if (jdbc.update("UPDATE " + history + " SET version=?,script=? WHERE version=?", String.valueOf(version), LEGACY.get(old-1).script(version), String.valueOf(old+1000)) != 1)
                    throw new IllegalStateException("History changed concurrently");
            }
        });
        // 旧 V16/V17 副本尚缺日志迁移，允许一次性补齐；不改变普通应用的 outOfOrder 配置。
        Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).outOfOrder(true).load().migrate();
        Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load().validate();
    }

    private static List<Migration> canonical() {
        var result = new ArrayList<>(LEGACY.subList(0, 13));
        result.addAll(List.of(LEGACY.get(16), LEGACY.get(17), LEGACY.get(13), LEGACY.get(14), LEGACY.get(15)));
        return result;
    }

    private static boolean matches(List<Map<String,Object>> rows, List<Migration> expected) {
        if (rows.size() != expected.size()) return false;
        var seen = new HashSet<Integer>();
        for (var row : rows) {
            Object raw = row.get("version");
            if (!(raw instanceof String version) || !version.matches("[1-9][0-9]?")) return false;
            int v = Integer.parseInt(version);
            if (v > expected.size() || !seen.add(v)) return false;
            var migration = expected.get(v-1);
            if (!migration.script(v).equals(row.get("script")) || !migration.description().equals(row.get("description"))
                || !Integer.valueOf(migration.checksum).equals(row.get("checksum")) || !"SQL".equals(row.get("type"))
                || !Boolean.TRUE.equals(row.get("success"))) return false;
        }
        return true;
    }
}
