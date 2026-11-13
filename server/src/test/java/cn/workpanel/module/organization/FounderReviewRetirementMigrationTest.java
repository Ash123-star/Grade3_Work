package cn.workpanel.module.organization;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;
class FounderReviewRetirementMigrationTest {
 @Test void v30PendingPeersAreRetiredWithoutApplyingCandidates() {
  String schema="founder_retire_"+UUID.randomUUID().toString().replace("-","");
  var source=new DriverManagerDataSource(System.getenv("DB_URL"),System.getenv("DB_USER"),System.getenv("DB_PASSWORD"));
  var jdbc=new JdbcTemplate(source);jdbc.execute("CREATE SCHEMA "+schema);
  try {
   Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).target("30").load().migrate();
   String url=System.getenv("DB_URL")+(System.getenv("DB_URL").contains("?")?"&":"?")+"currentSchema="+schema;
   var db=new JdbcTemplate(new DriverManagerDataSource(url,System.getenv("DB_USER"),System.getenv("DB_PASSWORD")));
   for(String id:new String[]{"a","b"}) db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status) VALUES (?,'default',?,'unused',?,?,'FOUNDER','ACTIVE')",id,id,id,id);
   for(String id:new String[]{"pending","approved","direct"}) {
    db.update("INSERT INTO review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason,status,approval_mode) VALUES (?,'default','a','COMPANY_ITEM','not-created',0,'{}','{\"title\":\"never apply\"}','migration',?,?)",id,id.equals("approved")?"APPROVED":"PENDING",id.equals("direct")?"DIRECT_MANAGER":"FOUNDER_PEER");
    db.update("INSERT INTO review_steps(request_id,company_id,applicant_id,reviewer_id,position,state) VALUES (?,'default','a','b',1,?)",id,id.equals("approved")?"APPROVED":"PENDING");
   }
   var before=db.queryForList("SELECT * FROM dashboard_items");
   var flyway=Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load();flyway.migrate();flyway.validate();
   assertEquals("34",flyway.info().current().getVersion().getVersion());
   assertEquals(1,db.queryForObject("SELECT count(*) FROM information_schema.columns WHERE table_schema=? AND table_name='personal_todos' AND column_name='end_date'",Integer.class,schema));
   assertEquals(1,db.queryForObject("SELECT count(*) FROM information_schema.columns WHERE table_schema=? AND table_name='attachments' AND column_name='storage_provider'",Integer.class,schema));
   assertEquals(3,db.queryForObject("SELECT count(*) FROM information_schema.tables WHERE table_schema=? AND table_name IN ('push_preferences','push_devices','push_deliveries')",Integer.class,schema));
   assertEquals("SUPERSEDED",db.queryForObject("SELECT status FROM review_requests WHERE id='pending'",String.class));
   assertEquals("SUPERSEDED",db.queryForObject("SELECT state FROM review_steps WHERE request_id='pending'",String.class));
   assertEquals("APPROVED",db.queryForObject("SELECT status FROM review_requests WHERE id='approved'",String.class));
   assertEquals("PENDING",db.queryForObject("SELECT status FROM review_requests WHERE id='direct'",String.class));
   assertEquals(before,db.queryForList("SELECT * FROM dashboard_items"));
   assertEquals(1,db.queryForObject("SELECT count(*) FROM audit_records WHERE type='REVIEW_SUPERSEDED'",Integer.class));
   assertEquals(1,db.queryForObject("SELECT count(*) FROM outbox_events WHERE type='REVIEW_SUPERSEDED'",Integer.class));
   assertEquals(0,flyway.migrate().migrationsExecuted);
  } finally {jdbc.execute("DROP SCHEMA "+schema+" CASCADE");}
 }
}
