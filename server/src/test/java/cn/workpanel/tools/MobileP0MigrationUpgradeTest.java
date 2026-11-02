package cn.workpanel.tools;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 真实 PostgreSQL 的 V21 → 最新版本升级验证：旧资料无损转写、phone 唯一且可空、
 * 审核历史保留、待审步骤替代与无审核人保持 PENDING；迁移不应用任何历史候选。
 */
class MobileP0MigrationUpgradeTest {
    private final DriverManagerDataSource source = new DriverManagerDataSource(
            System.getenv("DB_URL"), System.getenv("DB_USER"), System.getenv("DB_PASSWORD"));
    private final JdbcTemplate jdbc = new JdbcTemplate(source);

    @Test void legacyProfileValuesTransferOnlyWhenValidAndOtherKeysSurvive() {
        String schema = schema();
        try {
            flyway(schema, "21").migrate();
            String s = schema + ".";
            jdbc.update("INSERT INTO " + s + "users(id,company_id,account,password_hash,phone,name,role,status) VALUES "
                    + "('valid','default','acct-valid','hash','13800000001','合法资料','EMPLOYEE','ACTIVE'),"
                    + "('invalid','default','acct-invalid','hash','13800000002','非法资料','EMPLOYEE','ACTIVE'),"
                    + "('conflict','default','acct-conflict','hash','13800000003','冲突手机','EMPLOYEE','ACTIVE')");
            jdbc.update("UPDATE " + s + "users SET profile=jsonb_build_object('introduction','旧简介',"
                    + "'avatarAttachmentId','attachment-1','email','valid@example.com','gender','女','age','30',"
                    + "'phone','13800000001','privateKey','keep-me') WHERE id='valid'");
            jdbc.update("UPDATE " + s + "users SET profile=jsonb_build_object('introduction','保留简介',"
                    + "'email','not-an-email','gender',repeat('长',40),'age','30.5','ageText','未知') WHERE id='invalid'");
            jdbc.update("UPDATE " + s + "users SET profile=jsonb_build_object('phone','13900000009','note','保留') WHERE id='conflict'");

            flyway(schema, null).migrate();
            flyway(schema, null).validate();

            Map<String, Object> valid = jdbc.queryForMap("SELECT email,gender,age,phone,profile,employment_start_date FROM " + s + "users WHERE id='valid'");
            assertEquals("valid@example.com", valid.get("email"));
            assertEquals("女", valid.get("gender"));
            assertEquals(30, ((Number) valid.get("age")).intValue());
            assertEquals("13800000001", valid.get("phone"));
            assertNull(jdbc.queryForObject("SELECT profile->>'email' FROM " + s + "users WHERE id='valid'", String.class));
            assertNull(jdbc.queryForObject("SELECT profile->>'gender' FROM " + s + "users WHERE id='valid'", String.class));
            assertNull(jdbc.queryForObject("SELECT profile->>'age' FROM " + s + "users WHERE id='valid'", String.class));
            assertNull(jdbc.queryForObject("SELECT profile->>'phone' FROM " + s + "users WHERE id='valid'", String.class));
            assertEquals("旧简介", jdbc.queryForObject("SELECT profile->>'introduction' FROM " + s + "users WHERE id='valid'", String.class));
            assertEquals("attachment-1", jdbc.queryForObject("SELECT profile->>'avatarAttachmentId' FROM " + s + "users WHERE id='valid'", String.class));
            assertEquals("keep-me", jdbc.queryForObject("SELECT profile->>'privateKey' FROM " + s + "users WHERE id='valid'", String.class));

            assertNull(jdbc.queryForObject("SELECT email FROM " + s + "users WHERE id='invalid'", String.class));
            assertNull(jdbc.queryForObject("SELECT gender FROM " + s + "users WHERE id='invalid'", String.class));
            assertNull(jdbc.queryForObject("SELECT age FROM " + s + "users WHERE id='invalid'", Integer.class));
            assertEquals("not-an-email", jdbc.queryForObject("SELECT profile->>'email' FROM " + s + "users WHERE id='invalid'", String.class));
            assertEquals("30.5", jdbc.queryForObject("SELECT profile->>'age' FROM " + s + "users WHERE id='invalid'", String.class));
            assertEquals("未知", jdbc.queryForObject("SELECT profile->>'ageText' FROM " + s + "users WHERE id='invalid'", String.class));
            assertEquals("保留简介", jdbc.queryForObject("SELECT profile->>'introduction' FROM " + s + "users WHERE id='invalid'", String.class));

            assertEquals("13900000009", jdbc.queryForObject("SELECT profile->>'phone' FROM " + s + "users WHERE id='conflict'", String.class));
            assertEquals("13800000003", jdbc.queryForObject("SELECT phone FROM " + s + "users WHERE id='conflict'", String.class));
            assertEquals("保留", jdbc.queryForObject("SELECT profile->>'note' FROM " + s + "users WHERE id='conflict'", String.class));

            // 历史员工没有可信入职日期，迁移不得用 created_at 或迁移时间补猜。
            assertNull(jdbc.queryForObject("SELECT employment_start_date FROM " + s + "users WHERE id='valid'", java.sql.Date.class));
        } finally { drop(schema); }
    }

    @Test void phoneStaysUniqueWhileBecomingNullable() {
        String schema = schema();
        try {
            flyway(schema, null).migrate();
            String s = schema + ".";
            jdbc.update("INSERT INTO " + s + "users(id,company_id,account,password_hash,phone,name,role,status) VALUES "
                    + "('no-phone-1','default','acct-n1','hash',NULL,'无手机一','EMPLOYEE','ACTIVE'),"
                    + "('no-phone-2','default','acct-n2','hash',NULL,'无手机二','EMPLOYEE','ACTIVE')");
            assertEquals(2, jdbc.queryForObject("SELECT count(*) FROM " + s + "users WHERE phone IS NULL", Integer.class));
            jdbc.update("INSERT INTO " + s + "users(id,company_id,account,password_hash,phone,name,role,status) VALUES "
                    + "('dup-1','default','acct-d1','hash','13800000010','重复一','EMPLOYEE','ACTIVE')");
            assertThrows(Exception.class, () -> jdbc.update(
                    "INSERT INTO " + s + "users(id,company_id,account,password_hash,phone,name,role,status) VALUES "
                            + "('dup-2','default','acct-d2','hash','13800000010','重复二','EMPLOYEE','ACTIVE')"));
            assertThrows(Exception.class, () -> jdbc.update("UPDATE " + s + "users SET age=-1 WHERE id='no-phone-1'"));
        } finally { drop(schema); }
    }

    @Test void pendingChainsAreSupersededAndReroutedWithoutApplyingCandidates() {
        String schema = schema();
        try {
            flyway(schema, "21").migrate();
            String s = schema + ".";
            jdbc.update("INSERT INTO " + s + "users(id,company_id,account,password_hash,phone,name,role,status,company_reviewer,department_id) VALUES "
                    + "('founder','default','acct-founder','hash','13800000100','创始人','FOUNDER','ACTIVE',false,'product'),"
                    + "('admin-1','default','acct-admin1','hash','13800000101','管理员一','ADMIN','ACTIVE',true,'product'),"
                    + "('admin-2','default','acct-admin2','hash','13800000102','管理员二','ADMIN','ACTIVE',true,'product'),"
                    + "('manager','default','acct-manager','hash','13800000103','直属上级','LEADER','ACTIVE',false,'product'),"
                    + "('employee','default','acct-employee','hash','13800000104','普通成员','EMPLOYEE','ACTIVE',false,'product'),"
                    + "('orphan','default','acct-orphan','hash','13800000105','无上级','EMPLOYEE','ACTIVE',false,'product'),"
                    + "('applicant','default','acct-applicant','hash','13800000106','待确认成员','EMPLOYEE','PENDING',false,'product')");
            jdbc.update("INSERT INTO " + s + "reporting_relations(employee_id,manager_id,company_id) VALUES ('employee','manager','default')");

            // 注册成员确认：历史上曾分配给创始人；迁移后必须改由在职管理员审核，且候选不应用。
            jdbc.update("INSERT INTO " + s + "review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES "
                    + "('req-membership','default','applicant','MEMBERSHIP','applicant',1,"
                    + "'{\"status\":\"PENDING\"}'::jsonb,'{\"status\":\"ACTIVE\",\"departmentId\":\"product\"}'::jsonb,'成员确认','PENDING')");
            jdbc.update("INSERT INTO " + s + "review_steps(request_id,reviewer_id,applicant_id,position,company_id,state) VALUES "
                    + "('req-membership','founder','applicant',1,'default','PENDING')");

            // 普通关键变更：已决历史保留，旧待审步骤被替代，并只建当前直属上级一级。
            jdbc.update("INSERT INTO " + s + "review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES "
                    + "('req-direct','default','employee','USER','employee',2,'{\"name\":\"旧名\"}'::jsonb,"
                    + "'{\"name\":\"新名\"}'::jsonb,'成员资料变更','PENDING')");
            jdbc.update("INSERT INTO " + s + "review_steps(request_id,reviewer_id,applicant_id,position,company_id,state,reason,decided_at) VALUES "
                    + "('req-direct','admin-1','employee',1,'default','APPROVED','一级历史通过',now()),"
                    + "('req-direct','founder','employee',2,'default','PENDING',NULL,NULL)");

            // 无有效直属上级：保持 PENDING 且没有可执行步骤。
            jdbc.update("INSERT INTO " + s + "review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES "
                    + "('req-orphan','default','orphan','DEPARTMENT','product',1,'{}'::jsonb,'{\"name\":\"新部门\"}'::jsonb,'部门改名','PENDING')");

            // 已决申请：保留全部历史，模式标记为 LEGACY。
            jdbc.update("INSERT INTO " + s + "review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES "
                    + "('req-done','default','employee','COMPANY_ITEM','item-1',1,'{}'::jsonb,'{\"title\":\"已生效\"}'::jsonb,'公司重点','APPROVED')");
            jdbc.update("INSERT INTO " + s + "review_steps(request_id,reviewer_id,applicant_id,position,company_id,state,reason,decided_at) VALUES "
                    + "('req-done','admin-1','employee',1,'default','APPROVED','通过',now())");

            // 创始人本人的成员确认申请仍必须由管理员审批。
            jdbc.update("INSERT INTO " + s + "review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status) VALUES "
                    + "('req-founder-membership','default','founder','MEMBERSHIP','founder',1,'{}'::jsonb,"
                    + "'{\"status\":\"ACTIVE\",\"departmentId\":\"product\"}'::jsonb,'创始人成员确认','PENDING')");
            jdbc.update("INSERT INTO " + s + "review_steps(request_id,reviewer_id,applicant_id,position,company_id,state) VALUES "
                    + "('req-founder-membership','admin-2','founder',1,'default','PENDING')");

            flyway(schema, null).migrate();
            flyway(schema, null).validate();

            // 迁移不应用候选：待确认成员仍为 PENDING，且没有产生入职日期。
            assertEquals("PENDING", jdbc.queryForObject("SELECT status FROM " + s + "users WHERE id='applicant'", String.class));
            assertNull(jdbc.queryForObject("SELECT employment_start_date FROM " + s + "users WHERE id='applicant'", java.sql.Date.class));

            assertEquals("ADMIN_MEMBERSHIP", jdbc.queryForObject("SELECT approval_mode FROM " + s + "review_requests WHERE id='req-membership'", String.class));
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='req-membership' AND state='PENDING'", Integer.class));
            assertEquals("admin-1", jdbc.queryForObject("SELECT reviewer_id FROM " + s + "review_steps WHERE request_id='req-membership' AND state='PENDING'", String.class));
            assertEquals("SUPERSEDED", jdbc.queryForObject("SELECT state FROM " + s + "review_steps WHERE request_id='req-membership' AND reviewer_id='founder'", String.class));
            assertEquals("旧待审步骤由当前单级审核规则替代",
                    jdbc.queryForObject("SELECT reason FROM " + s + "review_steps WHERE request_id='req-membership' AND reviewer_id='founder'", String.class));
            assertNotNull(jdbc.queryForObject("SELECT decided_at FROM " + s + "review_steps WHERE request_id='req-membership' AND reviewer_id='founder'", java.sql.Timestamp.class));

            assertEquals("DIRECT_MANAGER", jdbc.queryForObject("SELECT approval_mode FROM " + s + "review_requests WHERE id='req-direct'", String.class));
            assertEquals("APPROVED", jdbc.queryForObject("SELECT state FROM " + s + "review_steps WHERE request_id='req-direct' AND position=1", String.class));
            assertEquals("SUPERSEDED", jdbc.queryForObject("SELECT state FROM " + s + "review_steps WHERE request_id='req-direct' AND reviewer_id='founder'", String.class));
            assertEquals("manager", jdbc.queryForObject("SELECT reviewer_id FROM " + s + "review_steps WHERE request_id='req-direct' AND state='PENDING'", String.class));
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='req-direct' AND state='PENDING'", Integer.class));

            assertEquals("PENDING", jdbc.queryForObject("SELECT status FROM " + s + "review_requests WHERE id='req-orphan'", String.class));
            assertEquals(0, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='req-orphan'", Integer.class));

            assertEquals("LEGACY", jdbc.queryForObject("SELECT approval_mode FROM " + s + "review_requests WHERE id='req-done'", String.class));
            assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM " + s + "review_steps WHERE request_id='req-done' AND state='APPROVED'", Integer.class));

            String founderMembershipReviewer = jdbc.queryForObject(
                    "SELECT reviewer_id FROM " + s + "review_steps WHERE request_id='req-founder-membership' AND state='PENDING'", String.class);
            assertNotEquals("founder", founderMembershipReviewer);
            assertEquals("ADMIN", jdbc.queryForObject("SELECT role FROM " + s + "users WHERE id=?", String.class, founderMembershipReviewer));

            List<Map<String, Object>> notifications = jdbc.queryForList(
                    "SELECT recipient_id,dedup_key FROM " + s + "outbox_events WHERE type='REVIEW_PENDING' ORDER BY recipient_id");
            assertFalse(notifications.isEmpty());
            assertEquals(notifications.size(), notifications.stream().map(row -> row.get("dedup_key")).distinct().count());
            for (Map<String, Object> row : notifications) {
                assertNotEquals("founder", row.get("recipient_id"));
            }
        } finally { drop(schema); }
    }

    @Test void aiReceiptMigrationKeepsJobsAndEnforcesOwnerAndReplayKey() {
        String schema=schema();
        try {
            flyway(schema,"22").migrate();
            String s=schema+".";
            jdbc.update("INSERT INTO "+s+"users(id,company_id,account,password_hash,name,role,status) VALUES ('owner','default','receipt-owner','hash','所有者','FOUNDER','ACTIVE'),('other','default','receipt-other','hash','其他人','EMPLOYEE','ACTIVE')");
            jdbc.update("INSERT INTO "+s+"ai_jobs(id,company_id,owner_id,state,input,output) VALUES ('job','default','owner','SUCCEEDED','{\"scope\":\"SELF\",\"sources\":[]}', '{\"summary\":\"保留建议\"}')");
            flyway(schema,null).migrate(); flyway(schema,null).validate();
            assertEquals("SUCCEEDED",jdbc.queryForObject("SELECT state FROM "+s+"ai_jobs WHERE id='job'",String.class));
            assertEquals("SELF",jdbc.queryForObject("SELECT input->>'scope' FROM "+s+"ai_jobs WHERE id='job'",String.class));
            String insert="INSERT INTO "+s+"ai_task_confirmations(id,company_id,owner_id,job_id,client_key,job_version,action_index,request_hash,source_refs,response) VALUES (?,'default',?,'job',?,?,?,'hash','{}','{}')";
            jdbc.update(insert,"receipt","owner","key",1,0);
            assertThrows(Exception.class,()->jdbc.update(insert,"duplicate","owner","key",1,0));
            assertThrows(Exception.class,()->jdbc.update(insert,"foreign-owner","other","key-2",1,0));
            assertThrows(Exception.class,()->jdbc.update(insert,"negative-version","owner","key-3",-1,0));
            assertThrows(Exception.class,()->jdbc.update(insert,"invalid-action","owner","key-4",1,3));
            assertEquals(1,jdbc.queryForObject("SELECT count(*) FROM "+s+"ai_task_confirmations",Integer.class));
        } finally { drop(schema); }
    }

    private Flyway flyway(String schema, String version) {
        var configuration = Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema);
        if (version != null) configuration.target(version);
        return configuration.load();
    }
    private String schema() {
        String schema = "mobile_p0_" + UUID.randomUUID().toString().replace("-", "");
        jdbc.execute("CREATE SCHEMA " + schema);
        var properties=new java.util.Properties();
        properties.setProperty("currentSchema",schema);
        source.setConnectionProperties(properties);
        return schema;
    }
    private void drop(String schema) { jdbc.execute("DROP SCHEMA " + schema + " CASCADE"); }
}
