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
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/** Real HTTP -> CustomerService -> PostgreSQL, including receipt migrations and ADMIN scope. */
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
        String path="/customers/"+id+"/benefits/"+benefitId+"/redemptions";
        var first=call(201,"POST",path,"admin",Map.of("note","入场"),"redeem-1");
        assertEquals(1,first.get("used").asInt());assertEquals(1,first.get("remaining").asInt());
        var second=call(201,"POST",path,"admin",Map.of(),"redeem-2");
        assertEquals(2,second.get("used").asInt());assertEquals(0,second.get("remaining").asInt());
        assertEquals(first,call(201,"POST",path,"admin",Map.of("note","重试"),"redeem-1"));
        call(409,"POST",path,"admin",Map.of(),"redeem-3");
        call(400,"POST",path,"admin",Map.of(),null);
        call(404,"POST",path,"otherAdmin",Map.of(),"redeem-1");
        var another=call(201,"POST","/customers","admin",Map.of("kind","INDIVIDUAL","name","另一客户"),null);
        call(404,"POST","/customers/"+another.get("id").asText()+"/benefits/"+benefitId+"/redemptions",
            "admin",Map.of(),"redeem-1");
        var history=call(200,"GET",path,"admin",null,null);
        assertEquals(2,history.size());
        assertFalse(history.get(0).has("used"));
        assertEquals(2,db.count("SELECT count(*) FROM audit_records WHERE company_id=? AND type='CUSTOMER_BENEFIT_REDEEMED' AND object_id=?",
            company,benefitId));
    }
    @Test void expiredDisabledAndArchivedBenefitsCannotRedeem()throws Exception{
        var customer=create();String id=customer.get("id").asText();
        var expired=call(201,"POST","/customers/"+id+"/benefits","admin",benefitBody("2000-01-01","2000-12-31",null),null);
        call(409,"POST","/customers/"+id+"/benefits/"+expired.get("id").asText()+"/redemptions","admin",Map.of(),"expired");
        var benefit=call(201,"POST","/customers/"+id+"/benefits","admin",benefitBody("2020-01-01","2100-12-31",null),null);
        String benefitId=benefit.get("id").asText();
        String path="/customers/"+id+"/benefits/"+benefitId+"/redemptions";
        var receipt=call(201,"POST",path,"admin",Map.of(),"original");
        assertTrue(receipt.get("remaining").isNull());
        db.update("UPDATE customer_benefits SET valid_from='2000-01-01',valid_to='2000-12-31' WHERE id=?",benefitId);
        assertEquals(receipt,call(201,"POST",path,"admin",Map.of(),"original"));
        db.update("UPDATE customer_benefits SET status='DISABLED' WHERE id=?",benefitId);
        call(409,"POST",path,"admin",Map.of(),"disabled");
        assertEquals(receipt,call(201,"POST",path,"admin",Map.of(),"original"));
        var archived=customerBody();archived.put("status","ARCHIVED");archived.put("version",1);
        call(200,"PUT","/customers/"+id,"admin",archived,null);
        call(409,"POST",path,"admin",Map.of(),"archived");
        assertEquals(receipt,call(201,"POST",path,"admin",Map.of(),"original"));
        call(400,"POST","/customers/"+id+"/benefits","admin",benefitBody("2026-12-31","2026-01-01",null),null);
    }
    @Test void simultaneousRetryReturnsOneReceiptAndOnlyConsumesOneUse()throws Exception{
        String customerId=create().get("id").asText();
        String prefix="/customers/"+customerId+"/benefits";
        var benefit=call(201,"POST",prefix,"admin",benefitBody("2020-01-01","2100-12-31",1),null);
        String path=prefix+"/"+benefit.get("id").asText()+"/redemptions";
        var start=new CyclicBarrier(2);
        Callable<JsonNode> attempt=()->{
            start.await(5,TimeUnit.SECONDS);
            return call(201,"POST",path,"admin",Map.of(),"same-key");
        };
        try(var requests=Executors.newVirtualThreadPerTaskExecutor()) {
            var first=requests.submit(attempt);
            var second=requests.submit(attempt);
            var receipt=first.get(25,TimeUnit.SECONDS);
            assertEquals(receipt,second.get(25,TimeUnit.SECONDS));
            assertEquals(1,receipt.get("used").asInt());
            assertEquals(0,receipt.get("remaining").asInt());
        }
        assertEquals(1,call(200,"GET",path,"admin",null,null).size());
        call(409,"POST",path,"admin",Map.of(),"new-key");
    }
    @Test void progressIsReturnedWithCustomer()throws Exception{
        var customer=create();String id=customer.get("id").asText();
        call(201,"POST","/customers/"+id+"/progress","admin",Map.of("stage","首次接待","note","已确认需求"),null);
        var detail=call(200,"GET","/customers/"+id,"admin",null,null);
        assertEquals(1,detail.get("progress").size());assertEquals("首次接待",detail.get("progress").get(0).get("stage").asText());
        call(404,"POST","/customers/"+id+"/progress","otherAdmin",Map.of("stage","x"),null);
    }
    @Test void companyProfileIsIdempotentAndContactsCannotMoveBetweenCustomers()throws Exception{
        var body=new LinkedHashMap<String,Object>(Map.of("kind","ENTERPRISE","name","企业客户",
            "ownerId",uid("employee"),"contacts",List.of(Map.of("name","李经理","role","采购"))));
        var start=new CyclicBarrier(2);
        Callable<JsonNode> attempt=()->{
            start.await(5,TimeUnit.SECONDS);
            return call(201,"POST","/customers","admin",body,"profile-create");
        };
        JsonNode created;
        try(var requests=Executors.newVirtualThreadPerTaskExecutor()) {
            var one=requests.submit(attempt);
            var two=requests.submit(attempt);
            created=one.get(25,TimeUnit.SECONDS);
            assertEquals(created,two.get(25,TimeUnit.SECONDS));
        }
        String path="/customers/"+created.path("id").asText();
        var contact=created.path("contacts").get(0);
        assertFalse(contact.path("id").asText().isBlank());
        assertEquals("employee",created.path("ownerName").asText());
        var list=call(200,"GET","/customers","admin",null,null);
        assertEquals(1,list.path("total").asInt());
        assertFalse(list.path("items").get(0).has("contacts"));
        assertEquals("CUSTOMER_POSSIBLE_DUPLICATE",call(409,"POST","/customers","admin",body,"check").path("code").asText());
        var confirmed=new LinkedHashMap<>(body);
        confirmed.put("confirmDuplicate",true);
        assertEquals("IDEMPOTENCY_CONFLICT",call(409,"POST","/customers","admin",confirmed,"profile-create").path("code").asText());
        var another=call(201,"POST","/customers","admin",confirmed,"confirmed");
        assertNotEquals(another.path("id"),created.path("id"));
        var changed=new LinkedHashMap<>(body);
        changed.put("version",1);
        changed.put("contacts",List.of(Map.of("id",contact.path("id").asText(),"name","新联系人")));
        changed.put("ownerId",uid("otherAdmin"));
        call(400,"PUT",path,"admin",changed,null);
        changed.put("ownerId",uid("employee"));
        call(400,"PUT","/customers/"+another.path("id").asText(),"admin",changed,null);
        var updated=call(200,"PUT",path,"admin",changed,null);
        assertEquals(contact.path("id"),updated.path("contacts").get(0).path("id"));
        call(409,"PUT",path,"admin",changed,null);
        call(404,"GET",path,"otherAdmin",null,null);
    }
    @Test void keyedAppendsAndMembershipRejectNewWritesAfterArchive()throws Exception{
        var customer=create();
        String path="/customers/"+customer.path("id").asText();
        var benefit=benefitBody("2020-01-01","2100-12-31",1);
        var stage=Map.of("stage","准备资料");
        var member=Map.of("mallMemberId","member-test","version",0);
        var receipt=call(201,"POST",path+"/benefits","admin",benefit,"grant");
        var entry=call(201,"POST",path+"/progress","admin",stage,"progress");
        assertEquals(entry,call(201,"POST",path+"/progress","admin",stage,"progress"));
        call(409,"POST",path+"/progress","admin",Map.of("stage","已回访"),"progress");
        call(200,"PUT",path+"/membership","admin",member,null);
        call(409,"PUT",path+"/membership","admin",member,null);
        var archived=customerBody();archived.put("status","ARCHIVED");archived.put("version",1);
        call(200,"PUT",path,"admin",archived,null);
        assertEquals(receipt,call(201,"POST",path+"/benefits","admin",benefit,"grant"));
        call(409,"POST",path+"/benefits","admin",benefit,"grant-again");
        call(409,"POST",path+"/progress","admin",stage,"progress-again");
        call(409,"PUT",path+"/membership","admin",Map.of("mallMemberId","other-member","version",1),null);
        var result=call(200,"GET",path,"admin",null,null);
        assertEquals(1,result.path("benefits").size());
        assertEquals(1,result.path("progress").size());
    }
}
