package cn.workpanel.module.organization;

import cn.workpanel.Db;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** 前端字段经HTTP写入真实PostgreSQL并回读；同时验证权限、版本、回执和统计范围。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT, properties={
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001", "app.jobs-enabled=false", "app.deepseek-key=local-mock-only"
})
class MobileDataContractIntegrationTest extends MemberBHttpSupport {
    final String today=LocalDate.now(ZoneId.of("Asia/Shanghai")).toString();

    HttpResponse<String> send(String method,String path,String who,Object body,String key) throws Exception {
        var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path))
            .timeout(Duration.ofSeconds(30)).header("Authorization","Bearer "+tokens.get(who));
        if(key!=null) request.header("Idempotency-Key",key);
        if(body!=null) request.header("Content-Type","application/json");
        return http.send(request.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
    JsonNode keyed(int status,String path,String who,Object body,String key) throws Exception {
        var response=send("POST",path,who,body,key);
        assertEquals(status,response.statusCode(),response.body()); return JSON.readTree(response.body());
    }
    Map<String,Object> draft(String title) {
        return Map.of("title",title,"participants",List.of(employee),"deadline",Instant.now().plusSeconds(86400).toString(),"content","交付说明");
    }
    String task() {
        String id=Db.id();
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body) VALUES (?,?,?,?,?,?::timestamptz,?::jsonb)",id,company,employee,founder,"真实任务",Instant.now().plusSeconds(86400).toString(),db.write(Map.of("content","任务内容","attachments",List.of())));
        db.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?)",id,employee,company);
        db.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body) VALUES (?,?,?,'DISPATCHED','{}')",company,id,founder);
        return id;
    }
    String job() {
        String id=Db.id();
        db.update("UPDATE users SET dispatch_enabled=true WHERE id=?",founder);
        var output=Map.of("summary","建议","sourceIds",List.of(),"nodes",List.of(),"actions",List.of(Map.of("title","跟进","sourceIds",List.of())));
        db.update("INSERT INTO ai_jobs(id,company_id,owner_id,state,input,output) VALUES (?,?,?,'SUCCEEDED',?::jsonb,?::jsonb)",id,company,founder,db.write(Map.of("sources",List.of(),"scope","SELF")),db.write(output));
        return id;
    }

    @Test void profileColumnsRoundTripAndRejectStaleDuplicateAndProtectedFields() throws Exception {
        db.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?),(?,?,?)",employee,leader,company,leader,director,company);
        var profile=Map.of("version",1,"phone","13987654321","email","member@example.com","gender","女","age",29,"introduction","保留简介");
        var saved=call(200,"PUT","/profiles/me",employee,profile);
        assertEquals("13987654321",saved.get("phone").asText()); assertEquals(29,saved.get("age").asInt());
        assertEquals("member@example.com",db.one("SELECT email FROM users WHERE id=?",employee).get("email"));
        assertEquals("保留简介",saved.at("/profile/introduction").asText()); assertTrue(saved.get("employmentStartDate").isNull());
        assertEquals("member@example.com",call(200,"GET","/profiles/"+employee,director,null).get("email").asText());
        call(403,"GET","/profiles/"+employee,colleague,null);
        call(409,"PUT","/profiles/me",employee,profile);
        call(409,"PUT","/profiles/me",colleague,Map.of("version",1,"phone","13987654321"));
        call(400,"PUT","/profiles/me",employee,Map.of("version",2,"role","ADMIN"));
        call(400,"PUT","/profiles/me",employee,Map.of("version",2,"age",-1));
        var clear=new LinkedHashMap<String,Object>(); clear.put("version",2); clear.put("phone",null); clear.put("email",null);
        var cleared=call(200,"PUT","/profiles/me",employee,clear);
        assertTrue(cleared.get("phone").isNull()); assertTrue(cleared.get("email").isNull());
        assertEquals(29,cleared.get("age").asInt()); assertEquals("保留简介",cleared.at("/profile/introduction").asText());
        db.update("DELETE FROM reporting_relations WHERE employee_id=?",employee);
        call(403,"GET","/profiles/"+employee,director,null);
    }

    @Test void teamDirectoryUsesCurrentOrganizationScope() throws Exception {
        assertEquals(2,call(200,"GET","/organization/teams",admin,null).size());
        assertEquals(1,call(200,"GET","/organization/teams",director,null).size());
        var own=call(200,"GET","/organization/teams",employee,null);
        assertEquals(1,own.size()); assertEquals(team,own.get(0).get("id").asText());
        assertTrue(own.get(0).has("version"));
    }

    @Test void feedbackAttachmentReturnAndResubmissionPersistAtomically() throws Exception {
        String task=task(),file=Db.id();
        db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data) VALUES (?,?,?,'result.txt','text/plain',?)",file,company,employee,"成果".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        call(200,"POST","/tasks/"+task+"/events",employee,Map.of("type","RECEIVED","version",1));
        call(200,"POST","/tasks/"+task+"/events",employee,Map.of("type","FEEDBACK","version",2,"text","第一轮成果","attachments",List.of(file)));
        assertEquals(task,db.one("SELECT task_id FROM attachments WHERE id=?",file).get("task_id"));
        call(200,"POST","/tasks/"+task+"/events",founder,Map.of("type","RETURNED","version",3,"text","补充说明"));
        assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",task).get("phase"));
        call(409,"POST","/tasks/"+task+"/events",employee,Map.of("type","FEEDBACK","version",3,"text","旧版本"));
        call(200,"POST","/tasks/"+task+"/events",employee,Map.of("type","FEEDBACK","version",4,"text","第二轮成果","attachments",List.of(file)));
        call(200,"POST","/tasks/"+task+"/events",founder,Map.of("type","ACCEPTED","version",5));
        assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='RETURNED'",task));
        assertEquals(2,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='FEEDBACK'",task));
        assertEquals(200,send("GET","/attachments/"+file,founder,null,null).statusCode());
        assertNotEquals(200,send("GET","/attachments/"+file,outside,null,null).statusCode());
    }

    @Test void aiConfirmationVersionAndConcurrentReplayCreateOnlyOneResult() throws Exception {
        String job=job(); var body=Map.of("version",1,"actionIndex",0,"task",draft("AI确认任务"));
        db.update("UPDATE ai_jobs SET version=2 WHERE id=?",job);
        keyed(409,"/ai/jobs/"+job+"/confirm-task",founder,body,"confirm");
        assertEquals(0,db.count("SELECT count(*) FROM ai_task_confirmations WHERE job_id=?",job));
        assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE company_id=?",company));
        var current=Map.of("version",2,"actionIndex",0,"task",draft("AI确认任务"));
        try(var pool=Executors.newFixedThreadPool(2)) {
            var one=pool.submit(()->keyed(200,"/ai/jobs/"+job+"/confirm-task",founder,current,"confirm"));
            var two=pool.submit(()->keyed(200,"/ai/jobs/"+job+"/confirm-task",founder,current,"confirm"));
            assertEquals(one.get(30,TimeUnit.SECONDS).get("id"),two.get(30,TimeUnit.SECONDS).get("id"));
        }
        db.update("UPDATE ai_jobs SET version=3 WHERE id=?",job);
        keyed(200,"/ai/jobs/"+job+"/confirm-task",founder,current,"confirm");
        keyed(409,"/ai/jobs/"+job+"/confirm-task",founder,Map.of("version",2,"actionIndex",0,"task",draft("不同任务")),"confirm");
        assertEquals(1,db.count("SELECT count(*) FROM ai_task_confirmations WHERE job_id=?",job));
        assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
        assertEquals(1,db.count("SELECT count(*) FROM review_requests WHERE company_id=? AND status='APPROVED'",company));
    }

    @Test void aiScopeAndStatisticsMatchPersistedFacts() throws Exception {
        task(); db.update("UPDATE users SET dispatch_enabled=true WHERE id=?",founder);
        for(String owner:List.of(founder,employee)) db.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES (?,?,?,?::date,'{\"work\":\"日报正文\"}',true,now())",Db.id(),company,owner,today);
        var self=call(200,"POST","/ai/jobs",founder,Map.of("date",today,"period","day","scope","SELF"));
        assertEquals("SELF",self.at("/input/scope").asText());
        for(var source:self.at("/input/sources")) assertEquals(founder.equals(source.path("ownerId").asText())||source.path("id").asText().startsWith("task:"),true);
        assertEquals(1,self.at("/input/candidates").size());
        var all=call(200,"POST","/ai/jobs",founder,Map.of("date",today,"period","day"));
        assertEquals("AUTHORIZED",all.at("/input/scope").asText());
        assertTrue(all.at("/input/sources").size()>self.at("/input/sources").size());
        call(400,"POST","/ai/jobs",founder,Map.of("date",today,"period","day","scope","ALL_COMPANIES"));
        String query="?date="+today+"&period=day&groupBy=person&ownerId="+employee;
        var stats=call(200,"GET","/analytics"+query,admin,null);
        var details=call(200,"GET","/analytics/details"+query+"&metric=diarySubmitted",admin,null);
        assertEquals(1,stats.get("diarySubmitted").asInt()); assertEquals(1,details.get("total").asInt());
        assertEquals(employee,details.get("items").get(0).get("owner_id").asText());
        var export=send("GET","/analytics/export"+query+"&resource=logs",admin,null,null);
        assertEquals(200,export.statusCode()); assertTrue(export.body().contains(employee)); assertFalse(export.body().contains(founder));
    }
}
