package cn.workpanel.module.personaltodo;

import cn.workpanel.*;
import com.fasterxml.jackson.databind.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import java.net.*;
import java.net.http.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** Real HTTP -> application -> PostgreSQL. Synthetic tenants, no production data. */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001","app.deepseek-key=local-mock-only","app.jobs-enabled=false"
})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PersonalTodoIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired ObjectMapper json;
    @Autowired StringRedisTemplate redis;
    final HttpClient http=HttpClient.newHttpClient();
    final String company="todo-"+UUID.randomUUID(),other="todo-other-"+UUID.randomUUID();
    final Map<String,String> tokens=new HashMap<>();
    String uid(String who){return (who.equals("other")?other:company)+"-"+who;}
    @BeforeAll void fixtures(){
        for(String c:List.of(company,other)) db.update("INSERT INTO companies(id,name) VALUES (?,?)",c,"Todo test");
        for(String who:List.of("alice","bob","admin","founder","leader","other","pending","disabled")) {
            String tenant=who.equals("other")?other:company;
            String role=switch(who){case "admin"->"ADMIN";case "founder"->"FOUNDER";case "leader"->"LEADER";default->"EMPLOYEE";};
            db.update("INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status,must_change_password) VALUES (?,?,?,'x',?,?,?,?,false)",uid(who),tenant,uid(who),who,"p-"+uid(who),role,who.equals("pending")?"PENDING":who.equals("disabled")?"DISABLED":"ACTIVE");
            String token=UUID.randomUUID().toString();tokens.put(who,token);
            db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(token),uid(who));
        }
    }
    @BeforeEach void reset(){
        db.update("DELETE FROM personal_todo_commands WHERE company_id IN (?,?)",company,other);
        db.update("DELETE FROM personal_todos WHERE company_id IN (?,?)",company,other);
        tokens.keySet().forEach(who->redis.delete("workpanel:api:"+uid(who)));
    }
    HttpResponse<String> send(String method,String path,String who,Object body,String key)throws Exception{
        var request=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).timeout(Duration.ofSeconds(20));
        if(who!=null)request.header("Authorization","Bearer "+tokens.get(who));
        if(key!=null)request.header("Idempotency-Key",key);
        if(body!=null)request.header("Content-Type","application/json");
        return http.send(request.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
    JsonNode call(int status,String method,String path,String who,Object body,String key)throws Exception{
        var r=send(method,path,who,body,key);assertEquals(status,r.statusCode(),r.body());return json.readTree(r.body());
    }
    Map<String,Object> createBody(){return new LinkedHashMap<>(Map.of("title","私人阅读计划","date","2026-11-04","note","仅本人可见"));}
    JsonNode create()throws Exception{return call(201,"POST","/personal-todos","alice",createBody(),UUID.randomUUID().toString());}
    Map<String,Object> update(JsonNode t,boolean completed){return new LinkedHashMap<>(Map.of("title",t.get("title").asText(),"note",t.get("note").asText(),"date",t.get("date").asText(),"completed",completed,"version",t.get("version").asInt()));}
    @Test void fullLifecycleAndCivilMonthCounts()throws Exception{
        var t=create();String path="/personal-todos/"+t.get("id").asText();
        assertEquals(t,call(200,"GET",path,"alice",null,null));
        var page=call(200,"GET","/personal-todos?date=2026-11-04","alice",null,null);assertEquals(1,page.get("total").asInt());assertTrue(page.get("nextCursor").isNull());
        var month=call(200,"GET","/personal-todos/calendar?month=2026-11","alice",null,null);
        assertEquals("2026-10-26",month.get("fromDate").asText());assertEquals("2026-12-07",month.get("toDate").asText());assertEquals(42,month.get("days").size());
        t=call(200,"PUT",path,"alice",update(t,true),"complete");assertTrue(t.get("completed").asBoolean());assertFalse(t.get("completedAt").isNull());
        var body=update(t,false);body.put("date","2027-01-02");t=call(200,"PUT",path,"alice",body,"move");assertTrue(t.get("completedAt").isNull());
        assertEquals(0,call(200,"GET","/personal-todos?date=2026-11-04","alice",null,null).get("total").asInt());
        var deleted=call(200,"DELETE",path+"?version="+t.get("version"),"alice",null,"delete");
        assertEquals(deleted,call(200,"DELETE",path+"?version="+t.get("version"),"alice",null,"delete"));call(404,"GET",path,"alice",null,null);
        assertEquals(0,call(200,"GET","/personal-todos?date=2027-01-02","alice",null,null).get("total").asInt());
        assertEquals(0,db.count("SELECT count(*) FROM audit_records WHERE object_id=?",t.get("id").asText()));
    }
    @Test void strictOwnerIsolationIncludesManagersAndAggregate()throws Exception{
        var t=create();String path="/personal-todos/"+t.get("id").asText();
        for(String who:List.of("bob","admin","founder","leader","other")){
            call(404,"GET",path,who,null,null);call(404,"PUT",path,who,update(t,true),"private");call(404,"DELETE",path+"?version=1",who,null,"private-delete");
            assertEquals(0,call(200,"GET","/personal-todos?date=2026-11-04",who,null,null).get("total").asInt());
            var calendar=call(200,"GET","/personal-todos/calendar?month=2026-11",who,null,null);for(var day:calendar.get("days"))assertEquals(0,day.get("total").asInt());
        }
        call(400,"GET","/personal-todos?date=2026-11-04&ownerId="+uid("alice"),"admin",null,null);
        call(403,"GET","/personal-todos?date=2026-11-04","pending",null,null);
        call(401,"GET","/personal-todos?date=2026-11-04","disabled",null,null);
        call(401,"GET","/personal-todos?date=2026-11-04",null,null,null);
    }
    @Test void invalidWritesNeverPersist()throws Exception{
        for(Object date:List.of("2026-02-30","1899-01-01",true)){var b=createBody();b.put("date",date);call(400,"POST","/personal-todos","alice",b,UUID.randomUUID().toString());}
        for(String key:List.of("ownerId","companyId","taskId")){var b=createBody();b.put(key,"x");call(400,"POST","/personal-todos","alice",b,key);}
        call(400,"POST","/personal-todos","alice",createBody(),null);
        var b=createBody();b.put("title","  ");call(400,"POST","/personal-todos","alice",b,"blank");
        call(400,"GET","/personal-todos?date=2026-11-04&limit=101","alice",null,null);
        call(400,"GET","/personal-todos?date=2026-11-04&date=2026-11-05","alice",null,null);
        call(400,"GET","/personal-todos/calendar?month=2026-13","alice",null,null);
        assertEquals(0,db.count("SELECT count(*) FROM personal_todos WHERE company_id=?",company));
    }
    @Test void responseLossReplayAndDifferentPayloadConflict()throws Exception{
        var t=call(201,"POST","/personal-todos","alice",createBody(),"retry-create");
        assertEquals(t,call(201,"POST","/personal-todos","alice",createBody(),"retry-create"));
        var changed=createBody();changed.put("title","另一个请求");assertEquals("IDEMPOTENCY_CONFLICT",call(409,"POST","/personal-todos","alice",changed,"retry-create").get("code").asText());
        String path="/personal-todos/"+t.get("id").asText();var body=update(t,true);
        var done=call(200,"PUT",path,"alice",body,"retry-complete");assertEquals(done,call(200,"PUT",path,"alice",body,"retry-complete"));
        assertEquals("VERSION_CONFLICT",call(409,"PUT",path,"alice",body,"another-command").get("code").asText());
        call(201,"POST","/personal-todos","bob",createBody(),"retry-create"); // Same key is isolated by owner.
        assertEquals(1,db.count("SELECT count(*) FROM personal_todos WHERE owner_id=?",uid("alice")));
    }
    @Test void parallelSameKeyCreatesOnceAndSameVersionOnlyOneWins()throws Exception{
        try(var executor=Executors.newFixedThreadPool(2)){
            var gate=new CountDownLatch(1);
            Callable<HttpResponse<String>> create=()->{gate.await();return send("POST","/personal-todos","alice",createBody(),"concurrent");};
            var a=executor.submit(create);var b=executor.submit(create);gate.countDown();
            var ra=a.get(30,TimeUnit.SECONDS);var rb=b.get(30,TimeUnit.SECONDS);assertEquals(201,ra.statusCode());assertEquals(ra.body(),rb.body());
            var t=json.readTree(ra.body());String path="/personal-todos/"+t.get("id").asText();
            var gate2=new CountDownLatch(1);var x=executor.submit(()->{gate2.await();return send("PUT",path,"alice",update(t,true),"v1-a");});var y=executor.submit(()->{gate2.await();return send("PUT",path,"alice",update(t,false),"v1-b");});gate2.countDown();
            var codes=new ArrayList<>(List.of(x.get(30,TimeUnit.SECONDS).statusCode(),y.get(30,TimeUnit.SECONDS).statusCode()));Collections.sort(codes);assertEquals(List.of(200,409),codes);
        }
    }
    @Test void paginationAndMonthBoundaryDoNotLoseEleventhRecord()throws Exception{
        for(int i=0;i<12;i++)call(201,"POST","/personal-todos","alice",createBody(),"page-"+i);
        var first=call(200,"GET","/personal-todos?date=2026-11-04&limit=10","alice",null,null);assertEquals(12,first.get("total").asInt());assertEquals("10",first.get("nextCursor").asText());
        var second=call(200,"GET","/personal-todos?date=2026-11-04&limit=10&cursor=10","alice",null,null);assertEquals(2,second.get("items").size());assertTrue(second.get("nextCursor").isNull());
        var leap=call(200,"GET","/personal-todos/calendar?month=2028-02","alice",null,null);assertEquals("2028-01-31",leap.get("fromDate").asText());
    }
    @Test void openApiPublishesPrivateContractsWithoutAdminAlias()throws Exception{
        var api=call(200,"GET","/openapi",null,null,null);
        assertTrue(api.path("paths").has("/api/personal-todos/calendar"));assertFalse(api.path("paths").has("/api/admin/workspace/personal-todos"));
        assertTrue(api.path("components").path("schemas").has("PersonalTodoCreate"));
    }
}
