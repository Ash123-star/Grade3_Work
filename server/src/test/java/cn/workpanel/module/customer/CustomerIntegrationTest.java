package cn.workpanel.module.customer;

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
import static org.junit.jupiter.api.Assertions.*;

/** Real HTTP -> CustomerService -> PostgreSQL, including V37 and ADMIN scope. */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001","app.deepseek-key=local-mock-only","app.jobs-enabled=false"
})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class CustomerIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired ObjectMapper json;
    @Autowired StringRedisTemplate redis;
    final HttpClient http=HttpClient.newHttpClient();
    final String company="cust-"+UUID.randomUUID(),other="cust-other-"+UUID.randomUUID();
    final Map<String,String> tokens=new HashMap<>();
    String uid(String who){return (who.equals("otherAdmin")?other:company)+"-"+who;}
    @BeforeAll void fixtures(){
        for(String c:List.of(company,other)) db.update("INSERT INTO companies(id,name) VALUES (?,?)",c,"Customer test");
        for(String who:List.of("admin","employee","pending","otherAdmin")) {
            String tenant=who.equals("otherAdmin")?other:company;
            String role=who.equals("employee")||who.equals("pending")?"EMPLOYEE":"ADMIN";
            db.update("INSERT INTO users(id,company_id,account,password_hash,name,phone,role,status,must_change_password) VALUES (?,?,?,'x',?,?,?,?,false)",uid(who),tenant,uid(who),who,"p-"+uid(who),role,who.equals("pending")?"PENDING":"ACTIVE");
            String token=UUID.randomUUID().toString();tokens.put(who,token);
            db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(token),uid(who));
        }
    }
    @BeforeEach void reset(){
        for(String c:List.of(company,other)) {
            db.update("DELETE FROM customer_benefit_redemptions WHERE company_id=?",c);
            db.update("DELETE FROM customer_progress WHERE company_id=?",c);
            db.update("DELETE FROM customer_benefits WHERE company_id=?",c);
            db.update("DELETE FROM customer_memberships WHERE company_id=?",c);
            db.update("DELETE FROM customers WHERE company_id=?",c);
        }
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
    Map<String,Object> customerBody(){return new LinkedHashMap<>(Map.of("kind","INDIVIDUAL","name","张三","phone","13800000000","externalId","mall-1"));}
    JsonNode create()throws Exception{return call(201,"POST","/customers","admin",customerBody(),null);}
    Map<String,Object> benefitBody(String from,String to,Integer max) {
        var body=new LinkedHashMap<String,Object>(Map.of("kind","ANNUAL_CARD","name","2026演出年卡","validFrom",from,"validTo",to));
        if(max!=null)body.put("maxUses",max);return body;
    }
    @Test void customerCrudExternalLookupAndAdminScope()throws Exception{
        var created=create();
        assertEquals("cus_",created.get("id").asText().substring(0,4));
        assertEquals(1,created.get("version").asInt());
        var byExternal=call(200,"GET","/customers/external/mall-1","admin",null,null);
        assertEquals(created.get("id"),byExternal.get("id"));
        var detail=call(200,"GET","/customers/"+created.get("id").asText(),"admin",null,null);
        assertEquals("张三",detail.get("customer").get("name").asText());assertTrue(detail.get("membership").isNull());
        var changed=customerBody();changed.put("name","李四");changed.put("version",1);
        var updated=call(200,"PUT","/customers/"+created.get("id").asText(),"admin",changed,null);
        assertEquals("李四",updated.get("name").asText());assertEquals(2,updated.get("version").asInt());
        call(409,"PUT","/customers/"+created.get("id").asText(),"admin",changed,null);
        call(403,"GET","/customers","employee",null,null);
        call(403,"GET","/customers","pending",null,null);
        call(404,"GET","/customers/"+created.get("id").asText(),"otherAdmin",null,null);
        var duplicate=customerBody();duplicate.put("name","重复");
        call(409,"POST","/customers","admin",duplicate,null);
    }
    @Test void membershipBenefitAndIdempotentRedemption()throws Exception{
        var customer=create();String id=customer.get("id").asText();
        var member=new LinkedHashMap<String,Object>(Map.of("mallMemberId","member-1","level","金卡","version",0));
        var saved=call(200,"PUT","/customers/"+id+"/membership","admin",member,null);
        assertEquals("member-1",saved.get("mallMemberId").asText());
        member.put("version",1);member.put("level","黑卡");
        assertEquals("黑卡",call(200,"PUT","/customers/"+id+"/membership","admin",member,null).get("level").asText());
        var benefit=call(201,"POST","/customers/"+id+"/benefits","admin",benefitBody("2020-01-01","2100-12-31",2),null);
        String benefitId=benefit.get("id").asText();
        var first=call(201,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of("note","入场"),"redeem-1");
        assertEquals(1,first.get("used").asInt());assertEquals(1,first.get("remaining").asInt());
        var replay=call(201,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of("note","入场"),"redeem-1");
        assertEquals(first.get("redemption").get("id"),replay.get("redemption").get("id"));assertEquals(1,replay.get("used").asInt());
        var history=call(200,"GET","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",null,null);
        assertEquals(1,history.size());
        call(201,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of(),"redeem-2");
        call(409,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of(),"redeem-3");
        call(400,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of(),null);
        call(404,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","otherAdmin",Map.of(),"foreign");
    }
    @Test void expiredDisabledAndArchivedBenefitsCannotRedeem()throws Exception{
        var customer=create();String id=customer.get("id").asText();
        var expired=call(201,"POST","/customers/"+id+"/benefits","admin",benefitBody("2000-01-01","2000-12-31",null),null);
        call(409,"POST","/customers/"+id+"/benefits/"+expired.get("id").asText()+"/redemptions","admin",Map.of(),"expired");
        var benefit=call(201,"POST","/customers/"+id+"/benefits","admin",benefitBody("2020-01-01","2100-12-31",null),null);
        String benefitId=benefit.get("id").asText();
        db.update("UPDATE customer_benefits SET status='DISABLED' WHERE id=?",benefitId);
        call(409,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of(),"disabled");
        var archived=customerBody();archived.put("status","ARCHIVED");archived.put("version",1);
        call(200,"PUT","/customers/"+id,"admin",archived,null);
        call(409,"POST","/customers/"+id+"/benefits/"+benefitId+"/redemptions","admin",Map.of(),"archived");
        call(400,"POST","/customers/"+id+"/benefits","admin",benefitBody("2026-12-31","2026-01-01",null),null);
    }
    @Test void progressIsReturnedWithCustomer()throws Exception{
        var customer=create();String id=customer.get("id").asText();
        call(201,"POST","/customers/"+id+"/progress","admin",Map.of("stage","首次接待","note","已确认需求"),null);
        var detail=call(200,"GET","/customers/"+id,"admin",null,null);
        assertEquals(1,detail.get("progress").size());assertEquals("首次接待",detail.get("progress").get(0).get("stage").asText());
        call(404,"POST","/customers/"+id+"/progress","otherAdmin",Map.of("stage","x"),null);
    }
}
