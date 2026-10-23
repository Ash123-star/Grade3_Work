package cn.workpanel.module.aiwork;

import cn.workpanel.Db;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import javax.sql.DataSource;
import java.util.UUID;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(properties={"app.jobs-enabled=false","app.memory-extract-enabled=false"})
class WorkMigrationTest {
    @Autowired DataSource source;@Autowired Db db;
    private void fixture(String schema,String sql) throws Exception{try(var connection=source.getConnection();var statement=connection.createStatement()){connection.setSchema(schema);statement.execute(sql);}}
    @Test void historicalSnapshotSurvivesAndCompositeKeysRejectOtherCompanies() throws Exception{
        String schema="work_upgrade_"+UUID.randomUUID().toString().replace("-","");
        try{
            org.flywaydb.core.Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).target("13").load().migrate();
            fixture(schema,"INSERT INTO "+schema+".users(id,company_id,account,password_hash,phone,name,role,status) VALUES ('old','default','old','unchanged','13900009999','历史员工','EMPLOYEE','ACTIVE')");
            fixture(schema,"INSERT INTO "+schema+".tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES ('old-task','default','old','old','历史任务',now()+interval '1 day','{}')");
            fixture(schema,"INSERT INTO "+schema+".attachments(id,company_id,owner_id,filename,content_type,data,task_id) VALUES ('old-file','default','old','历史.txt','text/plain','hello'::bytea,'old-task')");
            fixture(schema,"INSERT INTO "+schema+".ai_jobs(id,company_id,owner_id,state,input,output) VALUES ('old-ai','default','old','SUCCEEDED','{}','{\"summary\":\"历史结果\"}')");
            fixture(schema,"INSERT INTO "+schema+".review_requests(id,company_id,applicant_id,kind,target_id,expected_version,before_value,candidate,reason) VALUES ('old-review','default','old','TASK','old-task',1,'{}','{}','历史申请')");
            org.flywaydb.core.Flyway.configure().dataSource(source).schemas(schema).defaultSchema(schema).load().migrate();
            assertEquals("历史任务",db.one("SELECT title FROM "+schema+".tasks WHERE id='old-task'").get("title"));
            assertEquals(5,db.count("SELECT octet_length(data) FROM "+schema+".attachments WHERE id='old-file'"));
            assertEquals("SUCCEEDED",db.one("SELECT state FROM "+schema+".ai_jobs WHERE id='old-ai'").get("state"));
            assertEquals("PENDING",db.one("SELECT status FROM "+schema+".review_requests WHERE id='old-review'").get("status"));
            db.update("INSERT INTO "+schema+".companies(id,name) VALUES ('other','另一公司')");
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->db.update("INSERT INTO "+schema+".ai_work_items(id,company_id,owner_id) VALUES ('cross','other','old')"));
            db.update("INSERT INTO "+schema+".ai_work_items(id,company_id,owner_id) VALUES ('work','default','old')");
            db.update("INSERT INTO "+schema+".ai_work_steps(id,company_id,work_id,plan_version,step_key,action) VALUES ('step','default','work',0,'a','PREPARE')");
            assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->db.update("INSERT INTO "+schema+".ai_work_steps(id,company_id,work_id,plan_version,step_key,action) VALUES ('duplicate','default','work',0,'a','PREPARE')"));
        }finally{db.update("DROP SCHEMA "+schema+" CASCADE");}
    }
}
