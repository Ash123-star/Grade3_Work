package cn.workpanel.module.aiwork;

import cn.workpanel.*;
import com.fasterxml.jackson.databind.*;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.*;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.apache.poi.xwpf.usermodel.XWPFDocument;
import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.jupiter.api.Assertions.*;

/** 真实PG/Redis/HTTP与持久队列；模型和OCR仅为受控供应商，不代表真实供应商验收。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001","app.jobs-enabled=false","app.memory-extract-enabled=false","app.deepseek-key=test-only","app.ai-work-execution-enabled=true","app.ai-ocr-enabled=true","app.ai-work-poll-ms=100","app.ai-daily-tokens=500000"})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
// 同库的旧 Spring 测试上下文仍运行定时 worker；隔离其供应商配置，避免领取本夹具的作业。
@DirtiesContext(classMode=DirtiesContext.ClassMode.AFTER_CLASS)
class WorkIntegrationTest {
    static final java.util.concurrent.atomic.AtomicInteger ocrStatus=new java.util.concurrent.atomic.AtomicInteger(200);
    static final java.util.concurrent.atomic.AtomicInteger providerStatus=new java.util.concurrent.atomic.AtomicInteger(200);
    @Autowired MemoryModel memoryModel;
    static final AtomicReference<Double> ocrConfidence=new AtomicReference<>(.99);
    @LocalServerPort int port;@Autowired Db db;@Autowired StringRedisTemplate redis;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactionManager;
    @Autowired cn.workpanel.module.aiwork.application.WorkService workService;
    @Autowired cn.workpanel.module.aiwork.application.WorkExecutor workExecutor;
    @Autowired cn.workpanel.module.aiwork.infrastructure.WorkRepository workRepository;
    @Autowired cn.workpanel.shared.application.CurrentActors currentActors;
    @Autowired cn.workpanel.module.aiwork.application.DeliveryService deliveryService;
    @Autowired cn.workpanel.module.aiwork.application.WorkRetention retention;
    @Autowired cn.workpanel.module.attachment.application.AttachmentApplicationService attachmentService;
    @Autowired javax.sql.DataSource dataSource;
    static final ObjectMapper JSON=new ObjectMapper();static final AtomicReference<String> mode=new AtomicReference<>("TASK"),sourceId=new AtomicReference<>("");static final AtomicReference<Map<String,Object>> scriptedPlan=new AtomicReference<>();static final AtomicReference<String> input=new AtomicReference<>("");static final HttpServer provider=provider();
    final String company="work-it-"+Db.id();final Map<String,String> tokens=new HashMap<>(),ids=new HashMap<>();final HttpClient http=HttpClient.newHttpClient();
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r){r.add("app.deepseek-url",()->"http://127.0.0.1:"+provider.getAddress().getPort());r.add("app.ai-ocr-url",()->"http://127.0.0.1:"+provider.getAddress().getPort());}
    static HttpServer provider(){try{var server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);server.setExecutor(Executors.newCachedThreadPool(r->{var t=new Thread(r);t.setDaemon(true);return t;}));server.createContext("/extract",e->{e.getRequestBody().readAllBytes();if(ocrStatus.get()!=200){e.sendResponseHeaders(ocrStatus.get(),-1);e.close();return;}byte[] data=JSON.writeValueAsBytes(Map.of("parts",List.of(Map.of("text","请小李在2099年10月23日17:00交付成本表","locator","图片第1页","confidence",ocrConfidence.get())),"unverifiable",false));e.sendResponseHeaders(200,data.length);e.getResponseBody().write(data);e.close();});server.createContext("/chat/completions",e->{try{String request=new String(e.getRequestBody().readAllBytes(),StandardCharsets.UTF_8);input.set(request);if(providerStatus.get()!=200){e.sendResponseHeaders(providerStatus.get(),-1);return;}var data=JSON.readTree(JSON.readTree(request).at("/messages/1/content").asText());String owner="";for(var p:data.get("people"))if(p.get("name").asText().equals("小李"))owner=p.get("id").asText();Object result;
            if(scriptedPlan.get()!=null)result=scriptedPlan.get();
            else if(mode.get().equals("KNOWLEDGE"))result=Map.of("summary","查找公司资料","answer","差旅报销需要行程单","questions",List.of(),"actions",List.of(),"sourceIds",sourceId.get().isBlank()?List.of():List.of(sourceId.get()));
            else if(mode.get().equals("QUESTION"))result=Map.of("summary","整理任务","answer","","questions",List.of("请补充截止日期和时间"),"actions",List.of(),"sourceIds",List.of());
            else if(Set.of("CHECK","SUBMIT","OVERRIDE").contains(mode.get()))result=Map.of("summary","检查交付材料","answer","","questions",List.of(),"sourceIds",List.of(),"actions",List.of(Map.of("type",mode.get().equals("SUBMIT")?"SUBMIT_DELIVERY":"CHECK_DELIVERY","taskId",mode.get().equals("OVERRIDE")?sourceId.get():data.at("/task/id").asText(),"taskVersion",data.at("/task/version").asInt())));
            else {var action=new LinkedHashMap<String,Object>(Map.of("type","CREATE_TASK","title","交付成本表","requirements","提交成本明细","ownerId",owner,"ownerEvidence","小李","deadline","2099-10-23T17:00:00+08:00","deadlineEvidence","2099年10月23日17:00"));var actions=new ArrayList<Map<String,Object>>();actions.add(action);if(mode.get().equals("BATCH")){var second=new LinkedHashMap<>(action);second.put("title","交付第二份成本材料");second.put("dependsOn",List.of(1));actions.add(second);}result=Map.of("summary","准备成本表任务","answer","已整理任务要求","questions",List.of(),"sourceIds",sourceId.get().isBlank()?List.of():List.of(sourceId.get()),"actions",actions);}
            byte[] out=JSON.writeValueAsBytes(Map.of("choices",List.of(Map.of("message",Map.of("content",JSON.writeValueAsString(result)))),"usage",Map.of("total_tokens",100)));e.getResponseHeaders().set("Content-Type","application/json");e.sendResponseHeaders(200,out.length);e.getResponseBody().write(out);}finally{e.close();}});server.start();return server;}catch(IOException e){throw new RuntimeException(e);}}
    @BeforeAll void seed(){db.update("INSERT INTO companies(id,name,review_policy) VALUES (?,?,'{\"taskTeamReview\":false,\"taskDepartmentReview\":false}')",company,"办事测试");db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",company+"-d",company,"测试部");db.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?)",company+"-t",company,company+"-d","测试组");user("leader","LEADER","组长",true,false);user("alice","EMPLOYEE","小李",false,false);user("admin","ADMIN","管理员",true,false);user("reviewer","ADMIN","独立复核人",true,true);}
    void user(String key,String role,String name,boolean dispatch,boolean reviewer){String id=Db.id(),token=Db.id();ids.put(key,id);tokens.put(key,token);db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled,company_reviewer) VALUES (?,?,?,?,?,?,?, ?,?,'ACTIVE',?,?)",id,company,id,"x",id,name,company+"-d",company+"-t",role,dispatch,reviewer);db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(token),id);}
    @BeforeEach void reset(){ocrStatus.set(200);providerStatus.set(200);ocrConfidence.set(.99);mode.set("TASK");sourceId.set("");scriptedPlan.set(null);db.update("UPDATE ai_work_authorizations SET revoked_at=now() WHERE company_id=?",company);db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE company_id=? AND state='PUBLISHED'",company);db.update("UPDATE tasks SET title='历史夹具-'||id WHERE company_id=?",company);for(String id:ids.values())redis.delete("workpanel:memory-model:"+id);redis.delete(redis.keys("workpanel:api:*"));}
    JsonNode call(int expected,String method,String path,String who,Object body,String key)throws Exception{var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).timeout(Duration.ofSeconds(30)).header("Authorization","Bearer "+tokens.get(who));if(key!=null)b.header("Idempotency-Key",key);if(body!=null)b.header("Content-Type","application/json");var r=http.send(b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString());assertEquals(expected,r.statusCode(),path+" "+r.body());return r.headers().firstValue("content-type").orElse("").contains("application/octet-stream")?JSON.createObjectNode():JSON.readTree(r.body());}
    JsonNode await(String id,String state)throws Exception{return awaitAs(id,state,"leader");}
    JsonNode awaitAs(String id,String state,String who)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);JsonNode r;do{r=call(200,"GET","/ai/work-items/"+id,who,null,null);if(state.equals(r.get("state").asText()))return r;if(r.get("state").asText().equals("FAILED")&&!state.equals("FAILED"))fail(r.toString());Thread.sleep(250);}while(System.nanoTime()<end);fail(r.toString());return r;}
    String upload(String who,byte[] data,String name)throws Exception{return uploadResult(who,data,name,"",200).get("id").asText();}
    JsonNode uploadResult(String who,byte[] data,String name,String purpose,int expected)throws Exception{String boundary=Db.id();var bytes=new ByteArrayOutputStream();bytes.write(("--"+boundary+"\r\nContent-Disposition: form-data; name=\"file\"; filename=\""+name+"\"\r\nContent-Type: application/octet-stream\r\n\r\n").getBytes(StandardCharsets.UTF_8));bytes.write(data);bytes.write(("\r\n--"+boundary+"--\r\n").getBytes(StandardCharsets.UTF_8));var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/attachments?purpose="+purpose)).header("Authorization","Bearer "+tokens.get(who)).header("Content-Type","multipart/form-data; boundary="+boundary).POST(HttpRequest.BodyPublishers.ofByteArray(bytes.toByteArray())).build(),HttpResponse.BodyHandlers.ofString());assertEquals(expected,response.statusCode(),response.body());return JSON.readTree(response.body());}

    String published(String title,String content,String scope,String scopeId){String id=Db.id();var body=new LinkedHashMap<String,Object>(Map.of("title",title,"type","POLICY","content",content,"scopeKind",scope));if(scopeId!=null)body.put("scopeId",scopeId);db.update("INSERT INTO procedure_documents(id,company_id,owner_id,type,title,scope_kind,scope_id,state,active_version) VALUES (?,?,?,'POLICY',?,?,?,'PUBLISHED',1)",id,company,ids.get("admin"),title,scope,scopeId);db.update("INSERT INTO procedure_versions(company_id,document_id,version,body) VALUES (?,?,1,?::jsonb)",company,id,db.write(body));return id;}
    @Test void knownMaterialCitationIsNeverPromotedToFormalRuleAndUnknownCitationFails()throws Exception{
        String file=word("leader","请小李在2099年10月23日17:00交付成本表");sourceId.set(file);
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理材料任务","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        var ready=await(id,"WAITING_CONFIRMATION");assertEquals(0,ready.at("/plan/sources").size());assertEquals(file,ready.at("/plan/fileHashes/0/id").asText());assertEquals(1,ready.at("/plan/actions").size());
        sourceId.set(Db.id());
        String invalid=call(202,"POST","/ai/work-items","leader",Map.of("text","整理材料任务","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        assertEquals("AI_SCHEMA",await(invalid,"FAILED").at("/result/errorCode").asText());
        assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id IN (?,?)",id,invalid));
    }
    @RepeatedTest(20) void providerFailureRetriesThreeTimesAndBudgetStopsBeforeDisclosure()throws Exception{
        String who="fault-"+Db.id();user(who,"LEADER","故障验收",true,false);
        providerStatus.set(503);String id=call(202,"POST","/ai/work-items",who,Map.of("text","整理工作要求"),Db.id()).get("id").asText();
        try{
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
            while(!"FAILED".equals(db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"))&&System.nanoTime()<end){
                db.update("UPDATE ai_work_steps SET next_run_at=now() WHERE work_id=? AND state='PENDING'",id);workExecutor.tick();Thread.sleep(50);
            }
            assertEquals("FAILED",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));
            assertEquals(3,db.count("SELECT attempts FROM ai_work_steps WHERE work_id=?",id));
            assertEquals(3,db.count("SELECT count(*) FROM memory_model_calls WHERE owner_id=? AND state='FAILED'",ids.get(who)));
            assertEquals(1,db.count("SELECT count(*) FROM ai_work_messages WHERE work_id=?",id));
            assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
            providerStatus.set(200);
            db.update("INSERT INTO memory_model_calls(id,company_id,owner_id,purpose,request_hash,tokens,state) VALUES (?,?,?,'WORK_PLAN','budget-fixture',500000,'SUCCEEDED')",Db.id(),company,ids.get(who));
            long before=db.count("SELECT count(*) FROM memory_model_calls WHERE owner_id=?",ids.get(who));
            String budgetWork=call(202,"POST","/ai/work-items",who,Map.of("text","预算不足仍应保留本次材料"),Db.id()).get("id").asText();
            var failed=awaitAs(budgetWork,"FAILED",who);assertEquals("AI_BUDGET",failed.at("/result/errorCode").asText());
            assertEquals(before,db.count("SELECT count(*) FROM memory_model_calls WHERE owner_id=?",ids.get(who)));
            assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",budgetWork));
            call(200,"GET","/logs",who,null,null);
        }finally{providerStatus.set(200);}
    }
    @RepeatedTest(20) void ocrServiceFailureRetriesWithinBoundAndKeepsOriginalInput()throws Exception{
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");
        String file=upload("leader",png,"故障截图.png");ocrStatus.set(503);
        try{
            String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理截图要求","attachmentIds",List.of(file)),Db.id()).get("id").asText();
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
            while(!"FAILED".equals(db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"))&&System.nanoTime()<end){db.update("UPDATE ai_work_steps SET next_run_at=now() WHERE work_id=? AND state='PENDING'",id);workExecutor.tick();Thread.sleep(50);}
            assertEquals("OCR_UNAVAILABLE",await(id,"FAILED").at("/result/errorCode").asText());
            assertEquals(3,db.count("SELECT attempts FROM ai_work_steps WHERE work_id=?",id));
            assertEquals(1,db.count("SELECT count(*) FROM ai_work_messages WHERE work_id=?",id));
            assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
            assertEquals(0,db.count("SELECT count(*) FROM ai_file_extractions WHERE attachment_id=?",file));
        }finally{ocrStatus.set(200);}
    }
    @Test void modelOmissionCannotBypassConflictingFormalSources()throws Exception{
        String first=published("差旅费用申领","因公外出费用申领必须提交纸本税票","COMPANY",null);
        String second=published("报支简化规则","出差报销无须提供纸质发票","COMPANY",null);
        plan(List.of(createAction("交付成本表","alice","2099-10-23T17:00:00+08:00","2099年10月23日17:00")));
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","按差旅费用申领制度帮我创建任务，小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();
        var stopped=await(id,"WAITING_INPUT");assertTrue(stopped.at("/plan/sources").toString().contains(first));assertTrue(stopped.at("/plan/sources").toString().contains(second));
        assertTrue(stopped.at("/plan/questions").toString().contains("冲突"));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
    }
    @Test void relevantPolicyBeyondFirstFiftyHasLocatorPaginationAndRevocation()throws Exception{
        for(int n=0;n<55;n++)published("分页验收"+n,"普通行政目录","COMPANY",null);
        String target=published("异地差旅报销","普通说明\n".repeat(80)+"差旅报销需要行程单","COMPANY",null);
        String privateSource=published("保密差旅规定","差旅报销秘密材料","DEPARTMENT",company+"-other");
        var first=call(200,"GET","/procedures?search="+URLEncoder.encode("分页验收",StandardCharsets.UTF_8)+"&limit=30","leader",null,null);assertEquals(55,first.get("total").asInt());assertEquals(30,first.get("nextCursor").asInt());
        var second=call(200,"GET","/procedures?search="+URLEncoder.encode("分页验收",StandardCharsets.UTF_8)+"&cursor=30&limit=30","leader",null,null);assertEquals(25,second.get("items").size());assertEquals(-1,second.get("nextCursor").asInt());
        mode.set("KNOWLEDGE");sourceId.set(target);String id=call(202,"POST","/ai/work-items","leader",Map.of("text","异地差旅报销制度需要哪些材料"),Db.id()).get("id").asText();var done=await(id,"SUCCEEDED");assertEquals(target,done.at("/plan/sources/0/id").asText());assertTrue(done.at("/plan/sources/0/excerpts/0/locator").asText().contains("81"));assertTrue(input.get().contains("行程单"));assertFalse(input.get().contains(privateSource));assertFalse(input.get().contains("秘密材料"));
        db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE id=?",target);var stale=call(200,"GET","/ai/work-items/"+id,"leader",null,null);assertFalse(stale.get("planValid").asBoolean());assertFalse(stale.has("plan"));var list=call(200,"GET","/ai/work-items","leader",null,null);for(var item:list.get("items"))if(id.equals(item.get("id").asText()))assertFalse(item.at("/result/summary").asText().contains("行程单"));
        call(404,"GET","/procedures/"+privateSource,"leader",null,null);call(400,"GET","/procedures?limit=101","leader",null,null);
    }
    @Test void comparableConflictingSourcesAreVisibleAndStopWrites()throws Exception{
        String title="冲突成本办理制度";String first=published(title,"成本表必须提供明细","COMPANY",null);String second=published(title,"成本表不得包含明细","COMPANY",null);
        sourceId.set(first);String id=call(202,"POST","/ai/work-items","leader",Map.of("text","按冲突成本办理制度帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();var waiting=await(id,"WAITING_INPUT");assertTrue(waiting.at("/plan/questions").toString().contains("冲突"));assertTrue(waiting.at("/plan/sources").toString().contains(second));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE id IN (?,?)",first,second);
    }
    @Test void differentTitlesAndNewlyPublishedConflictsInvalidatePreviouslyPreparedWrites()throws Exception{
        String first=published("报价成本材料规范","报价成本表必须提供成本明细","COMPANY",null);
        sourceId.set(first);String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理报价成本材料规范：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();
        var ready=await(id,"WAITING_CONFIRMATION");String second=published("财务简化说明","报价成本表无需提供成本明细","COMPANY",null);
        try{
            var hidden=call(200,"GET","/ai/work-items/"+id,"leader",null,null);assertFalse(hidden.get("planValid").asBoolean());assertFalse(hidden.has("plan"));
            call(409,"POST","/ai/work-items/"+id+"/confirm","leader",confirmation(ready),Db.id());
            call(200,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",hidden.get("version").asInt(),"text","按报价成本材料规范帮我创建任务，小李在2099年10月23日17:00交付成本表"),Db.id());
            var stopped=await(id,"WAITING_INPUT");assertTrue(stopped.at("/plan/sources").toString().contains(second));assertTrue(stopped.at("/plan/answer").asText().contains("不一致"));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        }finally{db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE id IN (?,?)",first,second);}
    }
    Map<String,Object> confirmation(JsonNode item){var actions=new ArrayList<String>();for(int i=0;i<item.at("/plan/actions").size();i++)actions.add("action-"+(i+1));return Map.of("version",item.get("version").asInt(),"planVersion",item.get("planVersion").asInt(),"planHash",item.get("planHash").asText(),"confirmationId",item.get("confirmationId").asText(),"actions",actions);}
    Map<String,Object> createAction(String title,String owner,String deadline,String evidence){return new LinkedHashMap<>(Map.of("type","CREATE_TASK","title",title,"requirements","交付成本明细","ownerId",ids.get(owner),"ownerEvidence",owner.equals("alice")?"小李":"小王","deadline",deadline,"deadlineEvidence",evidence));}
    void plan(List<Map<String,Object>> actions){scriptedPlan.set(Map.of("summary","整理本次工作","answer","","questions",List.of(),"actions",actions,"sourceIds",List.of()));}
    @Test void missingDeadlineAndDuplicateNamesAreAskedTogetherThenSelectionResumes()throws Exception{
        user("same-name","EMPLOYEE","小李",false,false);
        try{
            plan(List.of(createAction("集中补充验收","alice","","")));
            String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请给小李整理一项任务，下周处理"),Db.id()).get("id").asText();var missing=await(id,"WAITING_INPUT");
            assertTrue(missing.at("/plan/questions").toString().contains("多位小李"));assertTrue(missing.at("/plan/questions").toString().contains("日期和时间"));assertEquals(0,missing.at("/plan/actions").size());
            plan(List.of(createAction("集中补充验收","alice","2099-10-23T17:00:00+08:00","2099年10月23日17:00")));
            call(200,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",missing.get("version").asInt(),"text","小李在2099年10月23日17:00交付成本表","answers",Map.of("ownerId",ids.get("alice"))),Db.id());
            var ready=await(id,"WAITING_CONFIRMATION");assertEquals("小李",ready.at("/plan/actions/0/evidence/owner").asText());call(200,"POST","/ai/work-items/"+id+"/confirm","leader",confirmation(ready),Db.id());assertEquals(1,await(id,"SUCCEEDED").get("receipts").size());
        }finally{db.update("UPDATE users SET status='DISABLED' WHERE id=?",ids.get("same-name"));}
    }
    @Test void personnelBeyondFirstHundredCannotHideDuplicateNamesOrSelectedPeople()throws Exception{
        String prefix="many-"+Db.id();
        db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status) SELECT ?||n::text,?,?||n::text,'x',?||n::text,'A-'||n::text,?,?,'EMPLOYEE','ACTIVE' FROM generate_series(1,105) n",prefix,company,prefix,prefix,company+"-d",company+"-t");
        user("late-duplicate","EMPLOYEE","小李",false,false);
        try{
            plan(List.of(createAction("完整范围人员校验","alice","2099-10-23T17:00:00+08:00","2099年10月23日17:00")));
            String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务，小李在2099年10月23日17:00交付材料"),Db.id()).get("id").asText();var waiting=await(id,"WAITING_INPUT");assertTrue(waiting.at("/plan/questions").toString().contains("多位小李"));assertEquals(0,waiting.get("receipts").size());
            call(200,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",waiting.get("version").asInt(),"text","选择这位小李，2099年10月23日17:00交付材料","answers",Map.of("ownerId",ids.get("alice"))),Db.id());var ready=await(id,"WAITING_CONFIRMATION");assertEquals(ids.get("alice"),ready.at("/plan/actions/0/payload/ownerId").asText());
            call(200,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",ready.get("version").asInt()),Db.id());
        }finally{db.update("UPDATE users SET status='DISABLED' WHERE company_id=? AND (id LIKE ? OR id=?)",company,prefix+"%",ids.get("late-duplicate"));}
    }
    @Test void independentAssigneesAndOversizedBatchesNeverSilentlyDropWork()throws Exception{
        user("bob","EMPLOYEE","小王",false,false);
        var actions=List.of(createAction("独立报价材料","alice","2099-10-23T17:00:00+08:00","2099年10月23日17:00"),createAction("独立成本材料","bob","2099-10-23T17:00:00+08:00","2099年10月23日17:00"));plan(actions);
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务，小李和小王分别在2099年10月23日17:00交付各自材料"),Db.id()).get("id").asText();var done=await(id,"SUCCEEDED");assertEquals(2,done.get("receipts").size());
        assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE id IN (SELECT result->>'taskId' FROM ai_action_receipts WHERE work_id=?) AND owner_id=?",id,ids.get("alice")));assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE id IN (SELECT result->>'taskId' FROM ai_action_receipts WHERE work_id=?) AND owner_id=?",id,ids.get("bob")));
        var six=new ArrayList<Map<String,Object>>();for(int i=0;i<6;i++)six.add(createAction("分批工作"+i,"alice","2099-10-23T17:00:00+08:00","2099年10月23日17:00"));plan(six);
        String grouped=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务，小李在2099年10月23日17:00完成六项工作"),Db.id()).get("id").asText();var waiting=await(grouped,"WAITING_INPUT");assertTrue(waiting.at("/plan/questions").toString().contains("最多 5 项"));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",grouped));assertEquals(1,waiting.get("messages").size());
    }
    @Test void batchExistingTasksUseEachGroundedClauseAndIgnoreModelSwappedIds()throws Exception{
        var tasks=new ArrayList<JsonNode>();for(String title:List.of("报价逐项核对","成本逐项核对")){var t=call(200,"POST","/tasks","leader",Map.of("title",title,"ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00","acceptanceChecklist",costChecklist()),Db.id());call(200,"POST","/tasks/"+t.get("id").asText()+"/events","alice",Map.of("version",t.get("version").asInt(),"type","RECEIVED","text","接收"),Db.id());tasks.add(t);}
        String file=word("alice","成本：10元");var actions=new ArrayList<Map<String,Object>>();for(int i=0;i<2;i++)actions.add(Map.of("type","CHECK_DELIVERY","taskId",tasks.get(1-i).get("id").asText(),"taskVersion",1,"taskEvidence","检查"+tasks.get(i).get("title").asText()));plan(actions);
        String id=call(202,"POST","/ai/work-items","alice",Map.of("text","检查报价逐项核对，检查成本逐项核对","attachmentIds",List.of(file)),Db.id()).get("id").asText();var done=awaitAs(id,"SUCCEEDED","alice");assertEquals(2,done.get("receipts").size());
        for(int i=0;i<2;i++)assertEquals(tasks.get(i).get("id").asText(),db.read(db.one("SELECT result FROM ai_action_receipts WHERE work_id=? AND step_key=?",id,"action-"+(i+1)).get("result")).get("taskId"));
        plan(List.of(Map.of("type","CHECK_DELIVERY","taskId",tasks.getFirst().get("id").asText())));
        String ambiguous=call(202,"POST","/ai/work-items","alice",Map.of("text","检查报价逐项核对，检查成本逐项核对","attachmentIds",List.of(file)),Db.id()).get("id").asText();awaitAs(ambiguous,"WAITING_INPUT","alice");assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",ambiguous));
    }
    @Test void similarTaskNeedsConcreteChoiceAndNeverOverwritesExisting()throws Exception{
        var task=call(200,"POST","/tasks","leader",Map.of("title","交付成本表","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00"),Db.id());String existing=task.get("id").asText();
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();var ready=await(id,"WAITING_CONFIRMATION");assertEquals(existing,ready.at("/plan/actions/0/similarTasks/0/id").asText());assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        call(200,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());var done=await(id,"SUCCEEDED");assertNotEquals(existing,done.at("/receipts/0/result/taskId").asText());assertEquals(1,db.one("SELECT version FROM tasks WHERE id=?",existing).get("version"));
    }
    @Test void companyPolicyReviewInvalidatesGrantsAndCannotBeBypassed()throws Exception{
        var policy=call(200,"GET","/ai/work-authorization-policy","leader",null,null);var grantBody=Map.of("action","CREATE_TASK","scope",Map.of("ownerIds",List.of(ids.get("alice")),"maxActions",2),"expiresAt",Instant.now().plusSeconds(3600).toString());
        var grant=call(200,"POST","/ai/work-authorizations","leader",grantBody,Db.id());String gid=grant.get("id").asText();
        call(403,"POST","/organization/review-policy/revisions","leader",Map.of("version",policy.get("version").asInt(),"reason","测试","aiWorkCreateAuthorization",false),null);
        call(400,"POST","/organization/review-policy/revisions","admin",Map.of("version",policy.get("version").asInt(),"reason","测试","aiWorkAuthorizationMaxDays",31),null);
        db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("admin"));
        String review=call(200,"POST","/organization/review-policy/revisions","admin",Map.of("version",policy.get("version").asInt(),"reason","暂停长期授权","aiWorkCreateAuthorization",false,"aiWorkAuthorizationMaxDays",1,"aiWorkAuthorizationMaxObjects",1,"aiWorkAuthorizationMaxActions",1),null).get("id").asText();
        assertTrue(call(200,"GET","/ai/work-authorization-policy","leader",null,null).get("canCreate").asBoolean());call(403,"POST","/reviews/"+review+"/decision","admin",Map.of("approve",true),null);call(200,"POST","/reviews/"+review+"/decision","reviewer",Map.of("approve",true),null);
        assertFalse(call(200,"GET","/ai/work-authorization-policy","leader",null,null).get("canCreate").asBoolean());var grants=call(200,"GET","/ai/work-authorizations","leader",null,null);for(var g:grants)if(gid.equals(g.get("id").asText()))assertFalse(g.get("effective").asBoolean());call(400,"POST","/ai/work-authorizations","leader",grantBody,Db.id());
        var next=call(200,"GET","/ai/work-authorization-policy","admin",null,null);String reopen=call(200,"POST","/organization/review-policy/revisions","admin",Map.of("version",next.get("version").asInt(),"reason","恢复授权入口","aiWorkCreateAuthorization",true,"aiWorkAuthorizationMaxDays",30,"aiWorkAuthorizationMaxObjects",100,"aiWorkAuthorizationMaxActions",5),null).get("id").asText();call(200,"POST","/reviews/"+reopen+"/decision","reviewer",Map.of("approve",true),null);
        var after=call(200,"GET","/ai/work-authorizations","leader",null,null);for(var g:after)if(gid.equals(g.get("id").asText()))assertFalse(g.get("effective").asBoolean());call(200,"POST","/ai/work-authorizations","leader",grantBody,Db.id());
    }
    @RepeatedTest(20) void revocationWaitsForAuthorizedCommitAndBlocksFollowingStep()throws Exception{
        var grant=call(200,"POST","/ai/work-authorizations","leader",Map.of("action","CREATE_TASK","scope",Map.of("ownerIds",List.of(ids.get("alice"))),"expiresAt",Instant.now().plusSeconds(3600).toString()),Db.id());String gid=grant.get("id").asText();
        var locked=new CountDownLatch(1);var release=new CountDownLatch(1);var pool=Executors.newFixedThreadPool(2);Actor actor=Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("leader")));var payload=Map.<String,Object>of("ownerId",ids.get("alice"));
        try{var commit=pool.submit(()->new org.springframework.transaction.support.TransactionTemplate(transactionManager).execute(status->{var a=currentActors.locked(actor);workService.lockAuthorizationPolicy(a);assertTrue(workService.preauthorized(a,"CREATE_TASK",payload,1));locked.countDown();try{assertTrue(release.await(5,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}return true;}));assertTrue(locked.await(5,TimeUnit.SECONDS));
            var revoke=pool.submit(()->{try{return call(200,"POST","/ai/work-authorizations/"+gid+"/revoke","leader",Map.of("version",1),Db.id());}catch(Exception e){throw new RuntimeException(e);}});assertThrows(TimeoutException.class,()->revoke.get(200,TimeUnit.MILLISECONDS));release.countDown();assertTrue(commit.get(5,TimeUnit.SECONDS));revoke.get(5,TimeUnit.SECONDS);assertFalse(workService.preauthorized(actor,"CREATE_TASK",payload,1));
        }finally{release.countDown();pool.shutdownNow();}
    }
    @RepeatedTest(20) void companyTighteningWaitsForInFlightSharedLockAndBlocksNextGrantUse()throws Exception{
        call(200,"POST","/ai/work-authorizations","leader",Map.of("action","CREATE_TASK","scope",Map.of("ownerIds",List.of(ids.get("alice"))),"expiresAt",Instant.now().plusSeconds(3600).toString()),Db.id());
        Actor actor=Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("leader")));var payload=Map.<String,Object>of("ownerId",ids.get("alice"));var locked=new CountDownLatch(1);var release=new CountDownLatch(1);var pool=Executors.newFixedThreadPool(2);
        try{var action=pool.submit(()->new org.springframework.transaction.support.TransactionTemplate(transactionManager).execute(status->{var a=currentActors.locked(actor);workService.lockAuthorizationPolicy(a);assertTrue(workService.preauthorized(a,"CREATE_TASK",payload,1));locked.countDown();try{assertTrue(release.await(5,TimeUnit.SECONDS));}catch(InterruptedException e){throw new RuntimeException(e);}return true;}));assertTrue(locked.await(5,TimeUnit.SECONDS));
            var tightening=pool.submit(()->db.update("UPDATE companies SET ai_authorization_revision=ai_authorization_revision+1 WHERE id=?",company));assertThrows(TimeoutException.class,()->tightening.get(200,TimeUnit.MILLISECONDS));release.countDown();assertTrue(action.get(5,TimeUnit.SECONDS));assertEquals(1,tightening.get(5,TimeUnit.SECONDS));assertFalse(workService.preauthorized(actor,"CREATE_TASK",payload,1));
        }finally{release.countDown();pool.shutdownNow();}
    }
    @RepeatedTest(20) void cancellationAndDeletionSerializeAfterCommitAndKeepOnlyCompletedBusiness()throws Exception{
        for(boolean delete:List.of(false,true)){
            org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);
            db.update("UPDATE tasks SET title='历史夹具-'||id WHERE company_id=?",company);
            mode.set("BATCH");String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务，小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();var ready=await(id,"EXECUTING");
            String suffix=Db.id().replace("-",""),function="it_stop_"+suffix,trigger="it_stop_trigger_"+suffix;int barrier=100000+new Random().nextInt(10000000);
            db.update("CREATE FUNCTION "+function+"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.work_id='"+id+"' AND NEW.step_key='action-1' THEN PERFORM pg_advisory_xact_lock("+barrier+"); END IF; RETURN NEW; END $$");
            db.update("CREATE TRIGGER "+trigger+" BEFORE INSERT ON ai_action_receipts FOR EACH ROW EXECUTE FUNCTION "+function+"()");
            var pool=Executors.newSingleThreadExecutor();
            try(var connection=dataSource.getConnection();var statement=connection.createStatement()){
                statement.execute("SELECT pg_advisory_lock("+barrier+")");org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);
                long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);while(db.count("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND objid=?::oid AND NOT granted",barrier)==0&&System.nanoTime()<end)Thread.sleep(25);
                assertEquals(1,db.count("SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND objid=?::oid AND NOT granted",barrier));
                // 第一事务已完成业务校验且尚未提交；后续领取停写，取消请求在同一actor锁之后等待。
                org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);
                var stop=pool.submit(()->{try{return delete?deleteWork(409,id,ready.get("version").asInt(),Db.id()):call(409,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",ready.get("version").asInt()),Db.id());}catch(Exception e){throw new RuntimeException(e);}});
                assertThrows(TimeoutException.class,()->stop.get(150,TimeUnit.MILLISECONDS));statement.execute("SELECT pg_advisory_unlock("+barrier+")");stop.get(10,TimeUnit.SECONDS);
                var current=call(200,"GET","/ai/work-items/"+id,"leader",null,null);assertEquals(1,current.get("receipts").size());String key=Db.id();int version=current.get("version").asInt();
                for(int replay=0;replay<20;replay++)if(delete)deleteWork(202,id,version,key);else call(200,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",version),key);
                assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE id IN (SELECT result->>'taskId' FROM ai_action_receipts WHERE work_id=?)",id));assertEquals(0,db.count("SELECT count(*) FROM ai_work_steps WHERE work_id=? AND state IN ('PENDING','RUNNING','WAITING')",id));
                if(delete){call(404,"GET","/ai/work-items/"+id,"leader",null,null);deleteWork(409,id,version+1,key);assertEquals(0,db.count("SELECT count(*) FROM ai_work_messages WHERE work_id=?",id));}
                else assertEquals("CANCELLED",call(200,"GET","/ai/work-items/"+id,"leader",null,null).get("state").asText());
            }finally{org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);pool.shutdownNow();db.update("DROP TRIGGER "+trigger+" ON ai_action_receipts");db.update("DROP FUNCTION "+function+"()");}
        }
    }
    JsonNode deleteWork(int expected,String id,int version,String key)throws Exception{var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/ai/work-items/"+id)).header("Authorization","Bearer "+tokens.get("leader")).header("Idempotency-Key",key).header("If-Match",Integer.toString(version)).DELETE().build(),HttpResponse.BodyHandlers.ofString());assertEquals(expected,response.statusCode(),response.body());return JSON.readTree(response.body());}
    @RepeatedTest(20) void stopOrMembershipRevocationBeforeActionPreventsAnyBusinessWrite()throws Exception{
        for(String change:List.of("cancel","delete","role","disabled","entry")){
            redis.delete("workpanel:memory-model:"+ids.get("leader"));redis.delete(redis.keys("workpanel:api:*"));
            org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);
            String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务，小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();var ready=await(id,"EXECUTING");
            try{
                switch(change){case "cancel"->call(200,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",ready.get("version").asInt()),Db.id());case "delete"->deleteWork(202,id,ready.get("version").asInt(),Db.id());case "role"->db.update("UPDATE users SET dispatch_enabled=false WHERE id=?",ids.get("leader"));case "disabled"->db.update("UPDATE users SET status='DISABLED' WHERE id=?",ids.get("leader"));case "entry"->org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);}
                org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);workExecutor.tick();
                if(Set.of("role","disabled").contains(change)){long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);while(!"FAILED".equals(db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"))&&System.nanoTime()<end)Thread.sleep(25);assertEquals("FAILED",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));}
                assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
            }finally{db.update("UPDATE users SET status='ACTIVE',dispatch_enabled=true WHERE id=?",ids.get("leader"));org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);var current=db.one("SELECT version,deleted_at FROM ai_work_items WHERE id=?",id);if(current.get("deleted_at")==null)call(200,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",current.get("version")),Db.id());org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);}
        }
    }
    @Test void screenshotClarificationConfirmationAndTwentyReplaysCreateOneTask()throws Exception{
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");String file=upload("leader",png,"聊天.png");String key=Db.id();var created=call(202,"POST","/ai/work-items","leader",Map.of("text","整理截图中的任务","attachmentIds",List.of(file)),key);String id=created.get("id").asText();var ready=await(id,"WAITING_CONFIRMATION");assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        var confirm=Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1"));String confirmKey=Db.id();call(200,"POST","/ai/work-items/"+id+"/confirm","leader",confirm,confirmKey);var done=await(id,"SUCCEEDED");String task=done.at("/receipts/0/result/taskId").asText();assertFalse(task.isBlank());
        var replayPool=Executors.newFixedThreadPool(20);try{var replays=new ArrayList<Future<?>>();for(int i=0;i<20;i++)replays.add(replayPool.submit(()->{try{call(200,"POST","/ai/work-items/"+id+"/confirm","leader",confirm,confirmKey);}catch(Exception e){throw new RuntimeException(e);}}));for(var replay:replays)replay.get(30,TimeUnit.SECONDS);}finally{replayPool.shutdownNow();}
        assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='DISPATCHED'",task));assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE type='AI_WORK_ACTION' AND object_id=?",id));
        call(404,"GET","/ai/work-items/"+id,"admin",null,null);call(403,"GET","/attachments/"+file,"alice",null,null);call(200,"GET","/tasks/"+task,"alice",null,null);
        call(409,"POST","/ai/work-items","leader",Map.of("text","不同内容"),key);
        assertTrue(input.get().contains("people"));assertFalse(input.get().contains("password_hash"));
        assertEquals(1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND type='TASK_DISPATCHED'",task));
    }
    @Test void explicitTaskAndEmployeeCannotDispatch()throws Exception{
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();await(id,"SUCCEEDED");
        String employee=call(202,"POST","/ai/work-items","alice",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);JsonNode result;do{result=call(200,"GET","/ai/work-items/"+employee,"alice",null,null);if(result.get("state").asText().equals("WAITING_INPUT"))break;Thread.sleep(100);}while(System.nanoTime()<end);assertEquals("WAITING_INPUT",result.get("state").asText());assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",employee));
    }
    @Test void clarificationUsesStructuredOwnerAndRejectsStaleOrUnknownSelection()throws Exception{
        mode.set("QUESTION");String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请整理任务要求"),Db.id()).get("id").asText();var pending=await(id,"WAITING_INPUT");int version=pending.get("version").asInt();
        call(404,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",version,"text","已选同事","answers",Map.of("ownerId","unknown-owner")),Db.id());
        call(409,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",version-1,"text","小李在2099年10月23日17:00交付成本表"),Db.id());mode.set("TASK");
        call(200,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",version,"text","小李在2099年10月23日17:00交付成本表","answers",Map.of("ownerId",ids.get("alice"))),Db.id());var ready=await(id,"WAITING_CONFIRMATION");
        assertEquals(ids.get("alice"),ready.at("/plan/actions/0/payload/ownerId").asText());assertTrue(input.get().contains("selectedOwnerId"));
        call(200,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());var done=await(id,"SUCCEEDED");assertEquals(1,done.get("receipts").size());
    }
    @Test void deliveryCheckSubmitAndHumanAcceptanceAreSeparate()throws Exception{
        var task=call(200,"POST","/tasks","leader",Map.of("title","交付测试","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00","acceptanceChecklist",List.of(Map.of("id","cost","title","提交成本明细","fileName","成本.docx","required",true))),Db.id());String id=task.get("id").asText();call(200,"POST","/tasks/"+id+"/events","alice",Map.of("type","RECEIVED","version",1),null);
        var bytes=new ByteArrayOutputStream();try(var doc=new XWPFDocument()){doc.createParagraph().createRun().setText("成本：10元");doc.write(bytes);}String file=upload("alice",bytes.toByteArray(),"成本.docx");String checkKey=Db.id();var checkBody=Map.of("taskVersion",2,"attachmentIds",List.of(file));var accepted=call(202,"POST","/tasks/"+id+"/delivery-checks","alice",checkBody,checkKey);String job=accepted.get("id").asText();JsonNode report=accepted;long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);while(Set.of("QUEUED","RUNNING").contains(report.get("state").asText())&&System.nanoTime()<end){Thread.sleep(100);report=call(200,"GET","/tasks/"+id+"/delivery-checks/"+job,"alice",null,null);}assertEquals("PASS",report.get("state").asText());assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",id).get("phase"));
        for(int i=0;i<20;i++)call(202,"POST","/tasks/"+id+"/delivery-checks","alice",checkBody,checkKey);assertEquals(1,db.count("SELECT count(*) FROM task_delivery_check_jobs WHERE task_id=?",id));call(404,"GET","/tasks/"+id+"/delivery-checks/"+job,"leader",null,null);
        var submit=Map.of("taskVersion",2,"checkId",report.get("id").asText(),"checkVersion",1,"attachmentIds",List.of(file),"mode","CHECKED","text","成本明细已交付");String key=Db.id();for(int i=0;i<20;i++)call(200,"POST","/tasks/"+id+"/deliveries","alice",submit,key);
        assertEquals("FEEDBACK",db.one("SELECT phase FROM tasks WHERE id=?",id).get("phase"));assertEquals(1,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",id));call(200,"GET","/attachments/"+file,"leader",null,null);call(409,"POST","/tasks/"+id+"/deliveries","alice",submit,Db.id());call(200,"POST","/tasks/"+id+"/events","leader",Map.of("type","ACCEPTED","version",3),null);
        assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='ACCEPTED'",id));
    }
    JsonNode deliveryTask(boolean received,List<Map<String,Object>> checklist)throws Exception{
        var task=call(200,"POST","/tasks","leader",Map.of("title","交付检查-"+Db.id(),"ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00","acceptanceChecklist",checklist),Db.id());
        return received?call(200,"POST","/tasks/"+task.get("id").asText()+"/events","alice",Map.of("type","RECEIVED","version",1),null):task;
    }
    List<Map<String,Object>> costChecklist(){return List.of(Map.of("id","cost","title","成本一致","fileName","成本.docx","field","成本","expected","10","unit","元","required",true));}
    String word(String who,String text)throws Exception{var bytes=new ByteArrayOutputStream();try(var doc=new XWPFDocument()){doc.createParagraph().createRun().setText(text);doc.write(bytes);}return upload(who,bytes.toByteArray(),"成本.docx");}
    String deliveryWork(JsonNode task,String who,String file,String instruction)throws Exception{return call(202,"POST","/ai/work-items",who,Map.of("text",instruction,"taskId",task.get("id").asText(),"taskVersion",task.get("version").asInt(),"attachmentIds",List.of(file)),Db.id()).get("id").asText();}
    void grantSubmit(String task)throws Exception{call(200,"POST","/ai/work-authorizations","alice",Map.of("action","SUBMIT_DELIVERY","scope",Map.of("taskIds",List.of(task)),"expiresAt",OffsetDateTime.now().plusDays(1).toString()),Db.id());}
    @Test void capabilitiesAndAiIntakeShareLimitsWithoutBreakingGeneralUploads()throws Exception{
        var capabilities=call(200,"GET","/ai/work-capabilities","alice",null,null).get("limits");assertEquals(50,capabilities.get("pdfPages").asInt());assertEquals(20000000,capabilities.get("imagePixels").asInt());assertEquals(50000,capabilities.get("spreadsheetCells").asInt());assertEquals(104857600,capabilities.get("expandedBytes").asInt());assertTrue(capabilities.get("formats").toString().contains("docx"));
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");
        assertEquals("FILE_TYPE_MISMATCH",uploadResult("alice",png,"伪装.pdf","AI_WORK",415).get("code").asText());assertEquals("UNSUPPORTED_FILE",uploadResult("alice",new byte[]{1},"旧.doc","AI_WORK",415).get("code").asText());
        assertTrue(uploadResult("alice",png,"截图.png","AI_WORK",200).has("id"));String legacy=upload("alice",new byte[]{1},"普通.txt");assertEquals("UNSUPPORTED_FILE",call(415,"POST","/ai/work-items","alice",Map.of("text","整理材料","attachmentIds",List.of(legacy)),Db.id()).get("code").asText());
        assertEquals("FILE_LIMIT",call(400,"POST","/ai/work-items","alice",Map.of("attachmentIds",List.of("a","b","c","d","e","f")),Db.id()).get("code").asText());
        // 存储中遗留超大文件仍须由AI入口拒绝；不依赖通用HTTP上传限额。
        String large=upload("alice",png,"超限.png");db.update("UPDATE attachments SET data=decode(repeat('00',10485761),'hex') WHERE id=?",large);assertEquals("FILE_LIMIT",call(400,"POST","/ai/work-items","alice",Map.of("attachmentIds",List.of(large)),Db.id()).get("code").asText());
        String exact=upload("alice",png,"合计.png");byte[] max=Arrays.copyOf(png,10485760);db.update("UPDATE attachments SET data=? WHERE id=?",max,exact);var actor=currentActors.fresh(new Actor(ids.get("alice"),company,"","","",false,false,false,"ACTIVE"));
        assertEquals(3,attachmentService.intake(actor,Collections.nCopies(3,exact)).size());assertEquals("FILE_LIMIT",assertThrows(ApiError.class,()->attachmentService.intake(actor,Collections.nCopies(4,exact))).code);
    }
    @Test void aiExplicitCheckThenSubmitProducesOneFeedbackAndWaitsForHumanAcceptance()throws Exception{
        mode.set("SUBMIT");var task=deliveryTask(true,costChecklist());String taskId=task.get("id").asText(),file=word("alice","成本：10元");String work=deliveryWork(task,"alice",file,"检查后提交");var done=awaitAs(work,"SUCCEEDED","alice");
        assertEquals("已提交，等待验收",done.at("/receipts/0/result/summary").asText());assertEquals("FEEDBACK",db.one("SELECT phase FROM tasks WHERE id=?",taskId).get("phase"));assertEquals(1,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='FEEDBACK'",taskId));assertEquals(0,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type IN ('ACCEPTED','ARCHIVED')",taskId));
        call(200,"GET","/attachments/"+file,"leader",null,null);assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE company_id=? AND type='TASK_DELIVERY_SUBMITTED' AND object_id IN (SELECT id FROM task_deliveries WHERE task_id=?)",company,taskId));
    }
    @Test void explicitSelectedTaskCheckCannotSucceedWithOnlyModelProse()throws Exception{
        var task=deliveryTask(false,List.of(Map.of("id","cost","title","核对金额","required",true,"field","金额","expected","10","unit","元")));
        String file=word("alice","金额：10元");
        scriptedPlan.set(Map.of("summary","仅文字说明","answer","材料已查看","questions",List.of(),"actions",List.of(),"sourceIds",List.of()));
        String id=call(202,"POST","/ai/work-items","alice",Map.of("text","只检查这份材料，不提交。","taskId",task.get("id").asText(),"taskVersion",task.get("version").asInt(),"attachmentIds",List.of(file)),Db.id()).get("id").asText();
        var done=awaitAs(id,"SUCCEEDED","alice");assertEquals("DELIVERY_CHECKED",done.at("/receipts/0/result/kind").asText());assertEquals("PASS",done.at("/receipts/0/result/report/state").asText());
        assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",task.get("id").asText()));
    }
    @Test void checkOnlyOverridesModelSubmitAndMatchingLongTermGrant()throws Exception{
        mode.set("SUBMIT");var task=deliveryTask(true,costChecklist());String taskId=task.get("id").asText();grantSubmit(taskId);String work=deliveryWork(task,"alice",word("alice","成本：10元"),"帮我检查交付材料，不要提交");var done=awaitAs(work,"SUCCEEDED","alice");
        assertEquals("CHECK_DELIVERY",done.at("/plan/actions/0/type").asText());assertEquals("PASS",done.at("/receipts/0/result/report/state").asText());assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",taskId).get("phase"));assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));
    }
    @Test void currentNoSubmitInstructionOverridesStandingGrantEvenWithoutCheckWord()throws Exception{
        mode.set("SUBMIT");var task=deliveryTask(true,costChecklist());String taskId=task.get("id").asText();grantSubmit(taskId);String work=deliveryWork(task,"alice",word("alice","成本：10元"),"先不要提交这份材料");var waiting=awaitAs(work,"WAITING_INPUT","alice");
        assertEquals(0,waiting.at("/plan/actions").size());assertEquals(0,waiting.get("receipts").size());assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",taskId).get("phase"));assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));
    }
    @Test void matchingGrantMaySubmitButNonmatchingAndRevokedGrantNeedConfirmation()throws Exception{
        mode.set("SUBMIT");var target=deliveryTask(true,costChecklist());String targetId=target.get("id").asText();grantSubmit(targetId);
        String work=deliveryWork(target,"alice",word("alice","成本：10元"),"处理这份交付材料");awaitAs(work,"SUCCEEDED","alice");assertEquals(1,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",targetId));
        var other=deliveryTask(true,costChecklist());String pending=deliveryWork(other,"alice",word("alice","成本：10元"),"处理这份交付材料");awaitAs(pending,"WAITING_CONFIRMATION","alice");assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",other.get("id").asText()));
        var grants=call(200,"GET","/ai/work-authorizations","alice",null,null);call(200,"POST","/ai/work-authorizations/"+grants.get(0).get("id").asText()+"/revoke","alice",Map.of("version",1),Db.id());
        var live=call(200,"GET","/tasks/"+targetId,"alice",null,null);String revoked=deliveryWork(live,"alice",word("alice","成本：10元"),"处理这份交付材料");awaitAs(revoked,"WAITING_CONFIRMATION","alice");assertEquals(1,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",targetId));
    }
    @Test void failedOrUnverifiableChecksNeverSubmitAndManualCannotBypassHardRules()throws Exception{
        mode.set("SUBMIT");var task=deliveryTask(true,costChecklist());String file=word("alice","成本：18元"),work=deliveryWork(task,"alice",file,"检查后提交");var pending=awaitAs(work,"WAITING_INPUT","alice");String taskId=task.get("id").asText();var report=pending.at("/receipts/0/result/report");assertEquals("NEEDS_FIX",report.get("state").asText());assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));
        call(409,"POST","/tasks/"+taskId+"/deliveries","alice",Map.of("taskVersion",2,"checkId",report.get("id").asText(),"checkVersion",1,"attachmentIds",List.of(file),"mode","MANUAL","text","请求人工核对"),Db.id());
        var legacy=deliveryTask(true,List.of());String legacyFile=word("alice","成本：10元");String legacyWork=deliveryWork(legacy,"alice",legacyFile,"检查后提交");var result=awaitAs(legacyWork,"WAITING_INPUT","alice");var uncertain=result.at("/receipts/0/result/report");assertEquals("UNVERIFIABLE",uncertain.get("state").asText());
        call(200,"POST","/tasks/"+legacy.get("id").asText()+"/deliveries","alice",Map.of("taskVersion",2,"checkId",uncertain.get("id").asText(),"checkVersion",1,"attachmentIds",List.of(legacyFile),"mode","MANUAL","text","已核对成本文件，请确认尚未约定的交付要求"),Db.id());
        assertEquals("UNVERIFIABLE",db.one("SELECT state FROM task_delivery_checks WHERE id=?",uncertain.get("id").asText()).get("state"));assertEquals("MANUAL",db.one("SELECT mode FROM task_deliveries WHERE task_id=?",legacy.get("id").asText()).get("mode"));
    }
    JsonNode awaitCheck(String task,String job)throws Exception{
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);JsonNode report;
        do{report=call(200,"GET","/tasks/"+task+"/delivery-checks/"+job,"alice",null,null);if(!Set.of("QUEUED","RUNNING").contains(report.get("state").asText()))return report;Thread.sleep(100);}while(System.nanoTime()<end);
        fail(report.toString());return report;
    }
    @Test void correctedMaterialsRequireNewReportAndDamagedOrBlurryFilesCannotPass()throws Exception{
        var task=deliveryTask(true,costChecklist());String id=task.get("id").asText(),wrong=word("alice","成本：18元"),fixed=word("alice","成本：10元");
        var initial=call(202,"POST","/tasks/"+id+"/delivery-checks","alice",Map.of("taskVersion",2,"attachmentIds",List.of(wrong)),Db.id());var bad=awaitCheck(id,initial.get("id").asText());assertEquals("NEEDS_FIX",bad.get("state").asText());
        call(409,"POST","/tasks/"+id+"/deliveries","alice",Map.of("taskVersion",2,"checkId",bad.get("id").asText(),"checkVersion",1,"attachmentIds",List.of(fixed),"mode","CHECKED","text","更正成本"),Db.id());
        String damaged=upload("alice",new byte[]{'P','K',3,4,0,0,0,0},"损坏.docx");var damagedJob=call(202,"POST","/tasks/"+id+"/delivery-checks","alice",Map.of("taskVersion",2,"attachmentIds",List.of(damaged)),Db.id());assertEquals("FAILED",awaitCheck(id,damagedJob.get("id").asText()).get("state").asText());assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",id));
        // 使用既有有效PNG，低识别置信度由受控供应商提供。
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");
        String blurry=upload("alice",png,"模糊.png");var scanTask=deliveryTask(true,List.of(Map.of("title","截图","fileName","模糊.png","required",true)));String scan=scanTask.get("id").asText();
        try{ocrConfidence.set(.3);var job=call(202,"POST","/tasks/"+scan+"/delivery-checks","alice",Map.of("taskVersion",2,"attachmentIds",List.of(blurry)),Db.id());assertEquals("UNVERIFIABLE",awaitCheck(scan,job.get("id").asText()).get("state").asText());}finally{ocrConfidence.set(.99);}
        var fresh=call(202,"POST","/tasks/"+id+"/delivery-checks","alice",Map.of("taskVersion",2,"attachmentIds",List.of(fixed)),Db.id());var good=awaitCheck(id,fresh.get("id").asText());assertEquals("PASS",good.get("state").asText());assertNotEquals(bad.get("id").asText(),good.get("id").asText());
        call(200,"POST","/tasks/"+id+"/deliveries","alice",Map.of("taskVersion",2,"checkId",good.get("id").asText(),"checkVersion",1,"attachmentIds",List.of(fixed),"mode","CHECKED","text","更正材料，请验收"),Db.id());assertEquals("FEEDBACK",db.one("SELECT phase FROM tasks WHERE id=?",id).get("phase"));assertEquals(0,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='ACCEPTED'",id));call(200,"POST","/tasks/"+id+"/events","leader",Map.of("type","ACCEPTED","version",3),null);assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='ACCEPTED'",id));
    }
    @Test void aiDoesNotImplicitlyReceiveOrLetReadableIssuerSubmit()throws Exception{
        mode.set("SUBMIT");var unreceived=deliveryTask(false,costChecklist());String work=deliveryWork(unreceived,"alice",word("alice","成本：10元"),"检查后提交");var failure=awaitAs(work,"FAILED","alice");assertEquals("INVALID_TRANSITION",failure.at("/result/errorCode").asText());assertEquals("DISPATCHED",db.one("SELECT phase FROM tasks WHERE id=?",unreceived.get("id").asText()).get("phase"));
        var received=deliveryTask(true,costChecklist());String invalid=deliveryWork(received,"leader",word("leader","成本：10元"),"检查后提交");assertEquals("FORBIDDEN",await(invalid,"FAILED").at("/result/errorCode").asText());assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id IN (?,?)",unreceived.get("id").asText(),received.get("id").asText()));
    }
    @Test void pureCheckRunsWithWritesDisabledWhileSubmitRemainsQueued()throws Exception{
        org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);String queued=null;
        try{mode.set("CHECK");var task=deliveryTask(true,costChecklist());String file=word("alice","成本：10元");String work=deliveryWork(task,"alice",file,"帮我检查材料");assertEquals("PASS",awaitAs(work,"SUCCEEDED","alice").at("/receipts/0/result/report/state").asText());
            mode.set("SUBMIT");queued=deliveryWork(task,"alice",file,"检查后提交");awaitAs(queued,"EXECUTING","alice");assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",task.get("id").asText()));
        }finally{if(queued!=null){var item=call(200,"GET","/ai/work-items/"+queued,"alice",null,null);call(200,"POST","/ai/work-items/"+queued+"/cancel","alice",Map.of("version",item.get("version").asInt()),Db.id());}org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);}
    }
    @Test void aiSubmissionReceiptFailureRollsBackFeedbackFilesAuditAndOutbox()throws Exception{
        mode.set("SUBMIT");var task=deliveryTask(true,costChecklist());String taskId=task.get("id").asText(),file=word("alice","成本：10元");String suffix=Db.id().replace("-",""),function="it_delivery_"+suffix,trigger="it_delivery_trigger_"+suffix;
        db.update("CREATE FUNCTION "+function+"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.company_id='"+company+"' THEN RAISE EXCEPTION 'injected receipt failure'; END IF; RETURN NEW; END $$");db.update("CREATE TRIGGER "+trigger+" BEFORE INSERT ON ai_action_receipts FOR EACH ROW EXECUTE FUNCTION "+function+"()");String work;
        try{work=deliveryWork(task,"alice",file,"检查后提交");awaitAs(work,"FAILED","alice");assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",taskId).get("phase"));assertEquals(0,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='FEEDBACK'",taskId));assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));assertEquals(0,db.count("SELECT count(*) FROM attachment_bindings WHERE attachment_id=? AND resource_type='DELIVERY'",file));assertEquals(0,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND dedup_key LIKE ?",taskId,"task-event:"+taskId+":3:%"));}
        finally{db.update("DROP TRIGGER "+trigger+" ON ai_action_receipts");db.update("DROP FUNCTION "+function+"()");}
        var failed=call(200,"GET","/ai/work-items/"+work,"alice",null,null);call(200,"POST","/ai/work-items/"+work+"/retry","alice",Map.of("version",failed.get("version").asInt()),Db.id());awaitAs(work,"SUCCEEDED","alice");assertEquals(1,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",taskId));assertEquals(1,db.count("SELECT count(*) FROM task_events WHERE task_id=? AND type='FEEDBACK'",taskId));
    }
    @Test void procedureRequiresIndependentPublicationAndPreservesActiveVersion()throws Exception{
        String id=call(200,"POST","/procedures","admin",Map.of("title","交付制度","type","POLICY","content","交付须提供成本明细"),Db.id()).get("id").asText();call(404,"GET","/procedures/"+id,"alice",null,null);db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("admin"));var review=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",1,"reason","发布制度"),Db.id());String request=review.get("id").asText();call(403,"POST","/reviews/"+request+"/decision","admin",Map.of("approve",true,"reason",""),null);
        call(200,"POST","/reviews/"+request+"/decision","reviewer",Map.of("approve",true,"reason","核对通过"),null);assertEquals("交付制度",call(200,"GET","/procedures/"+id,"alice",null,null).get("title").asText());var draft=call(200,"GET","/procedures/"+id+"?draft=true","admin",null,null);assertEquals(2,draft.get("version").asInt());call(200,"POST","/procedures/"+id+"/revisions","admin",Map.of("version",2,"candidate",Map.of("title","新版交付制度","type","POLICY","content","交付须提供报价")),Db.id());assertEquals("交付制度",call(200,"GET","/procedures/"+id,"alice",null,null).get("title").asText());
    }
    @Test void publicationWithoutReviewerStaysPendingAndFinalVersionConflictRollsBackApproval()throws Exception{
        db.update("UPDATE users SET department_id=NULL,team_id=NULL WHERE id=?",ids.get("admin"));
        String id=call(200,"POST","/procedures","admin",Map.of("title","独立复核边界","type","POLICY","content","报价需要成本材料"),Db.id()).get("id").asText();String request;
        try{
            db.update("UPDATE users SET company_reviewer=false WHERE company_id=?",company);
            request=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",1,"reason","发布资料"),Db.id()).get("id").asText();
            assertEquals("PENDING",call(200,"GET","/reviews/"+request,"admin",null,null).get("status").asText());assertEquals(0,db.count("SELECT count(*) FROM review_steps WHERE request_id=?",request));call(404,"GET","/procedures/"+id,"alice",null,null);
        }finally{db.update("UPDATE users SET company_reviewer=true WHERE id=?",ids.get("reviewer"));}
        call(200,"POST","/reviews/"+request+"/reroute","admin",null,null);
        call(200,"POST","/procedures/"+id+"/revisions","admin",Map.of("version",1,"candidate",Map.of("title","独立复核边界","type","POLICY","content","报价需要新版成本材料")),Db.id());
        call(409,"POST","/reviews/"+request+"/decision","reviewer",Map.of("approve",true),null);assertEquals("PENDING",call(200,"GET","/reviews/"+request,"admin",null,null).get("status").asText());assertEquals(0,db.count("SELECT count(*) FROM review_steps WHERE request_id=? AND state<>'PENDING'",request));call(404,"GET","/procedures/"+id,"alice",null,null);
        call(200,"POST","/reviews/"+request+"/decision","reviewer",Map.of("approve",false,"reason","资料已经更新，请重新申请"),null);
        String fresh=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",2,"reason","发布更新资料"),Db.id()).get("id").asText();call(200,"POST","/reviews/"+fresh+"/decision","reviewer",Map.of("approve",true),null);assertEquals(2,call(200,"GET","/procedures/"+id,"alice",null,null).get("version").asInt());
    }
    @Test void expiredPolicyAndAbsentRulesNeverProduceAnInventedCompanyAnswer()throws Exception{
        db.update("UPDATE users SET department_id=NULL,team_id=NULL WHERE id=?",ids.get("admin"));
        String id=call(200,"POST","/procedures","admin",Map.of("title","过期差旅制度","type","POLICY","content","差旅报销需要旧版行程单","effectiveFrom","2020-01-01T00:00:00Z","effectiveTo","2021-01-01T00:00:00Z"),Db.id()).get("id").asText();String request=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",1,"reason","历史资料"),Db.id()).get("id").asText();call(200,"POST","/reviews/"+request+"/decision","reviewer",Map.of("approve",true),null);call(404,"GET","/procedures/"+id,"alice",null,null);
        mode.set("KNOWLEDGE");String work=call(202,"POST","/ai/work-items","leader",Map.of("text","差旅报销需要什么正式材料"),Db.id()).get("id").asText();var answer=await(work,"SUCCEEDED");assertTrue(answer.at("/plan/answer").asText().contains("没有找到"));assertEquals(0,answer.at("/plan/sources").size());assertEquals(0,answer.get("receipts").size());assertFalse(input.get().contains("旧版行程单"));
    }
    @Test void unsupportedApplicationsCannotClaimSubmissionOrInventTaskOperations()throws Exception{
        String source=published("差旅申请制度","差旅报销须提供行程单，在财务系统提交","COMPANY",null);long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);
        scriptedPlan.set(Map.of("summary","报销已提交","answer","报销申请已提交，编号FAKE-001","questions",List.of(),"sourceIds",List.of(source),"actions",List.of(Map.of("type","CREATE_TASK","title","冒充报销申请","requirements","派发报销","ownerId",ids.get("alice"),"ownerEvidence","小李","deadline","2099-10-23T17:00:00+08:00","deadlineEvidence","2099年10月23日17:00"))));
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请按差旅制度提交报销申请，小李在2099年10月23日17:00出差"),Db.id()).get("id").asText();var result=await(id,"SUCCEEDED");assertEquals(0,result.at("/plan/actions").size());assertEquals(0,result.get("receipts").size());assertEquals(before,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));assertTrue(result.at("/plan/answer").asText().contains("仍需"));assertFalse(result.at("/plan/answer").asText().contains("FAKE-001"));
    }
    @Test void scopedAuthorizationSelectionRevocationAndExpiredConfirmation()throws Exception{
        var options=call(200,"GET","/ai/work-authorization-options?action=CREATE_TASK&search="+URLEncoder.encode("小李",StandardCharsets.UTF_8),"leader",null,null);
        assertEquals(ids.get("alice"),options.at("/items/0/id").asText());assertEquals("测试组",options.at("/items/0/team").asText());
        call(403,"GET","/ai/work-authorization-options?action=CREATE_TASK","alice",null,null);
        var grant=call(200,"POST","/ai/work-authorizations","leader",Map.of("action","CREATE_TASK","scope",Map.of("ownerIds",List.of(ids.get("alice"))),"expiresAt",Instant.now().plusSeconds(3600).toString()),Db.id());
        var grants=call(200,"GET","/ai/work-authorizations","leader",null,null);assertTrue(grants.toString().contains("小李"));
        call(200,"POST","/ai/work-authorizations/"+grant.get("id").asText()+"/revoke","leader",Map.of("version",1),Db.id());
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理小李在2099年10月23日17:00交付成本表的要求"),Db.id()).get("id").asText();
        var ready=await(id,"WAITING_CONFIRMATION");assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        db.update("UPDATE ai_work_confirmations SET expires_at=now()-interval '1 second' WHERE work_id=?",id);
        call(409,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());
        call(200,"POST","/ai/work-items/"+id+"/cancel","leader",Map.of("version",ready.get("version").asInt()),Db.id());
        assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        assertEquals("CANCELLED",call(200,"GET","/ai/work-items/"+id,"leader",null,null).get("state").asText());
    }
    @Test void formalTemplatePrefillsOnlySafeFieldsAndWithdrawsAfterReview()throws Exception{
        var template=call(200,"POST","/procedures","admin",Map.of("title","办理模板","type","TEMPLATE","content","申请人：{{姓名}}；部门：{{部门}}；事由：{{事由}}；审核：{{审核人}}"),Db.id());String id=template.get("id").asText();
        db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("admin"));
        var review=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",1,"reason","发布模板"),Db.id());call(200,"POST","/reviews/"+review.get("id").asText()+"/decision","reviewer",Map.of("approve",true,"reason","通过"),null);
        var draft=call(200,"POST","/procedures/"+id+"/template-draft","alice",Map.of("version",1,"reason","领取材料"),null);assertTrue(draft.get("content").asText().contains("申请人：小李"));assertTrue(draft.get("content").asText().contains("{{审核人}}"));assertTrue(draft.get("unfilled").asBoolean());
        call(400,"POST","/procedures/"+id+"/template-draft","alice",Map.of("version",1,"reason","x","role","ADMIN"),null);
        call(409,"POST","/procedures/"+id+"/template-draft","alice",Map.of("version",2,"reason","x"),null);
        call(403,"GET","/procedures/"+id+"/comparison","alice",null,null);
        var comparison=call(200,"GET","/procedures/"+id+"/comparison","admin",null,null);assertEquals("办理模板",comparison.at("/published/title").asText());
        var withdrawal=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",2,"withdraw",true,"reason","模板已过期"),Db.id());call(200,"GET","/procedures/"+id,"alice",null,null);call(200,"POST","/reviews/"+withdrawal.get("id").asText()+"/decision","reviewer",Map.of("approve",true,"reason","同意撤回"),null);call(404,"GET","/procedures/"+id,"alice",null,null);
    }
    @RepeatedTest(20) void receiptFailureRollsBackTaskAuditAndOutboxThenRetriesOnce()throws Exception{
        String suffix=Db.id().replace("-",""),function="it_receipt_"+suffix,trigger="it_receipt_trigger_"+suffix;
        long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);
        db.update("CREATE FUNCTION "+function+"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.company_id='"+company+"' THEN RAISE EXCEPTION 'injected receipt failure'; END IF; RETURN NEW; END $$");
        db.update("CREATE TRIGGER "+trigger+" BEFORE INSERT ON ai_action_receipts FOR EACH ROW EXECUTE FUNCTION "+function+"()");String id;
        try{id=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();await(id,"FAILED");assertEquals(before,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));assertEquals(0,db.count("SELECT count(*) FROM audit_records WHERE type='AI_WORK_ACTION' AND object_id=?",id));}
        finally{db.update("DROP TRIGGER "+trigger+" ON ai_action_receipts");db.update("DROP FUNCTION "+function+"()");}
        var failed=call(200,"GET","/ai/work-items/"+id,"leader",null,null);call(200,"POST","/ai/work-items/"+id+"/retry","leader",Map.of("version",failed.get("version").asInt()),Db.id());await(id,"SUCCEEDED");assertEquals(before+1,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
    }
    @Test void retryWithExpiredPlanRequiresFreshConfirmationAndCreatesOneTask()throws Exception{
        String id=Db.id(),fingerprint=currentActors.fingerprint(Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("leader"))));
        db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,title,plan_version) VALUES (?,?,?,'FAILED','过期计划事项',1)",id,company,ids.get("leader"));
        db.update("INSERT INTO ai_work_messages(id,company_id,work_id,sequence,body) VALUES (?,?,?,1,'{\"text\":\"请帮我创建任务：小李在2099年10月23日17:00交付成本表\"}'::jsonb)",Db.id(),company,id);
        db.update("INSERT INTO ai_work_plans(company_id,work_id,version,body,hash,permission_fingerprint,expires_at) VALUES (?,?,1,'{}'::jsonb,'expired-hash',?,now()-interval '1 second')",company,id,fingerprint);
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state,error_code) VALUES (?,?,?,1,'action-1','CREATE_TASK','FAILED','WORK_FAILED')",Db.id(),company,id);
        long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);

        var failed=call(200,"GET","/ai/work-items/"+id,"leader",null,null);
        var retry=call(200,"POST","/ai/work-items/"+id+"/retry","leader",Map.of("version",failed.get("version").asInt()),Db.id());
        assertEquals("QUEUED",retry.get("state").asText());
        var ready=await(id,"WAITING_CONFIRMATION");assertEquals(2,ready.get("planVersion").asInt());assertNotEquals("expired-hash",ready.get("planHash").asText());
        assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));assertEquals(before,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
        var confirmation=Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1"));
        call(200,"POST","/ai/work-items/"+id+"/confirm","leader",confirmation,Db.id());var done=await(id,"SUCCEEDED");
        assertEquals(1,done.get("receipts").size());assertEquals(before+1,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
    }
    @Test void twentyExpiredLeasesRecoverAndRejectOldFences()throws Exception{
        mode.set("QUESTION");
        for(int i=0;i<20;i++){
            redis.delete("workpanel:memory-model:"+ids.get("leader"));redis.delete(redis.keys("workpanel:api:*"));String id=Db.id(),step=Db.id();
            db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state) VALUES (?,?,?,'PREPARING')",id,company,ids.get("leader"));db.update("INSERT INTO ai_work_messages(id,company_id,work_id,sequence,body) VALUES (?,?,?,1,'{\"text\":\"整理任务\"}')",Db.id(),company,id);
            db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state,fence,attempts,lease_until) VALUES (?,?,?,0,'prepare-1','PREPARE','RUNNING',4,1,now()-interval '1 second')",step,company,id);
            await(id,"WAITING_INPUT");assertEquals(5,db.count("SELECT fence FROM ai_work_steps WHERE id=?",step));assertEquals(0,db.update("UPDATE ai_work_steps SET state='SUCCEEDED' WHERE id=? AND fence=4 AND state='RUNNING'",step));assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        }
    }
    @Test void exhaustedLeaseShowsRecoverableFailureInsteadOfStayingRunning()throws Exception{
        String id=Db.id(),step=Db.id();db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state) VALUES (?,?,?,'PREPARING')",id,company,ids.get("leader"));
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state,fence,attempts,lease_until) VALUES (?,?,?,0,'prepare-1','PREPARE','RUNNING',7,3,now()-interval '1 second')",step,company,id);
        assertEquals("WORK_TIMEOUT",await(id,"FAILED").at("/result/errorCode").asText());assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
    }
    @Test void twentyUnknownOrExpiredCommittedOutcomesRestoreOnlyRecordedResults()throws Exception{
        org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);
        try{
            var works=new ArrayList<String>();long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);
            for(int i=0;i<20;i++)works.add(seedOutcome(i%2==0?"UNKNOWN":"RUNNING",true,false));
            assertEquals(before+20,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
            for(int replay=0;replay<20;replay++)workExecutor.reconcileOutcomes();
            for(String id:works){assertEquals("SUCCEEDED",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));assertEquals("SUCCEEDED",db.one("SELECT state FROM ai_work_steps WHERE work_id=?",id).get("state"));assertEquals(5,db.count("SELECT fence FROM ai_work_steps WHERE work_id=?",id));assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));}
            assertEquals(before+20,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
        }finally{org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);}
    }
    @Test void missingOutcomeIsProvenBeforeRetryAndMismatchedReceiptNeverReexecutes()throws Exception{
        org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",false);var workIds=new ArrayList<String>();
        try{
            String uncommitted=seedOutcome("UNKNOWN",false,false),mismatch=seedOutcome("UNKNOWN",true,true);workIds.addAll(List.of(uncommitted,mismatch));
            db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,payload) VALUES (?,?,?,1,'action-2','CREATE_TASK','{}'::jsonb)",Db.id(),company,mismatch);
            long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);workExecutor.reconcileOutcomes();
            assertEquals("PENDING",db.one("SELECT state FROM ai_work_steps WHERE work_id=?",uncommitted).get("state"));assertEquals("QUEUED",db.one("SELECT state FROM ai_work_items WHERE id=?",uncommitted).get("state"));
            assertEquals("UNKNOWN",db.one("SELECT state FROM ai_work_steps WHERE work_id=? AND step_key='action-1'",mismatch).get("state"));assertEquals("RECONCILING",db.one("SELECT state FROM ai_work_items WHERE id=?",mismatch).get("state"));
            org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);workExecutor.tick();
            assertEquals("PENDING",db.one("SELECT state FROM ai_work_steps WHERE work_id=? AND step_key='action-2'",mismatch).get("state"));assertEquals(before,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
        }finally{try{var actor=Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("leader")));for(String id:workIds)workService.command(actor,id,"cancel",Map.of("version",db.one("SELECT version FROM ai_work_items WHERE id=?",id).get("version")),Db.id());}finally{org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);org.springframework.test.util.ReflectionTestUtils.setField(workService,"executionEnabled",true);}}
    }
    @Test void unknownCommitBlocksNewInstructionsAndStopFencesEveryPendingOutcome()throws Exception{
        org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);
        try{
            for(boolean delete:List.of(false,true)){
                String id=seedOutcome("RUNNING",true,false);var step=db.one("SELECT * FROM ai_work_steps WHERE work_id=?",id);
                org.springframework.test.util.ReflectionTestUtils.invokeMethod(workExecutor,"fail",step,new org.springframework.transaction.TransactionSystemException("simulated commit acknowledgement lost"));
                assertEquals("UNKNOWN",db.one("SELECT state FROM ai_work_steps WHERE work_id=?",id).get("state"));
                assertEquals("RECONCILING",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));
                var actor=currentActors.fresh(new Actor(ids.get("leader"),company,"","","",false,false,false,"ACTIVE"));
                int version=((Number)db.one("SELECT version FROM ai_work_items WHERE id=?",id).get("version")).intValue();
                // 结果核对推迟到未来，避免定时器先于本次指令处理。
                db.update("UPDATE ai_work_steps SET next_run_at=now()+interval '1 hour' WHERE work_id=?",id);
                org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);
                assertEquals("OUTCOME_PENDING",call(409,"POST","/ai/work-items/"+id+"/messages","leader",Map.of("version",version,"text","再创建一次相同任务"),Db.id()).get("code").asText());
                org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);
                long fence=db.count("SELECT fence FROM ai_work_steps WHERE work_id=?",id);String key=Db.id();
                for(int replay=0;replay<20;replay++)workService.command(actor,id,delete?"delete":"cancel",Map.of("version",version),key);
                assertEquals("CANCELLED",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));assertEquals("CANCELLED",db.one("SELECT state FROM ai_work_steps WHERE work_id=?",id).get("state"));assertEquals(fence+1,db.count("SELECT fence FROM ai_work_steps WHERE work_id=?",id));
                workExecutor.reconcileOutcomes();assertEquals("CANCELLED",db.one("SELECT state FROM ai_work_items WHERE id=?",id).get("state"));assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE id IN (SELECT result->>'taskId' FROM ai_action_receipts WHERE work_id=?)",id));
            }
        }finally{org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);}
    }
    @Test void exhaustedUnknownOutcomeDistinguishesFailureFromPartialAndNeverHidesUnresolved()throws Exception{
        org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",false);
        try{
            String failed=seedOutcome("UNKNOWN",false,false),partial=seedOutcome("SUCCEEDED",true,false),unresolved=seedOutcome("UNKNOWN",true,true);
            db.update("UPDATE ai_work_steps SET attempts=3 WHERE work_id=?",failed);
            for(String id:List.of(partial,unresolved))db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state,attempts) VALUES (?,?,?,1,'action-2','CREATE_TASK',?,3)",Db.id(),company,id,id.equals(partial)?"UNKNOWN":"FAILED");
            db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state,dependencies) VALUES (?,?,?,1,'action-3','CREATE_TASK','PENDING','[\"action-2\"]'::jsonb)",Db.id(),company,unresolved);
            workExecutor.propagateDependencyFailures();assertEquals("RECONCILING",db.one("SELECT state FROM ai_work_items WHERE id=?",unresolved).get("state"));
            workExecutor.reconcileOutcomes();assertEquals("FAILED",db.one("SELECT state FROM ai_work_items WHERE id=?",failed).get("state"));assertEquals("PARTIAL",db.one("SELECT state FROM ai_work_items WHERE id=?",partial).get("state"));assertEquals("RECONCILING",db.one("SELECT state FROM ai_work_items WHERE id=?",unresolved).get("state"));
        }finally{org.springframework.test.util.ReflectionTestUtils.setField(workService,"enabled",true);}
    }
    String seedOutcome(String state,boolean committed,boolean mismatch)throws Exception{
        String id=Db.id();var payload=Map.<String,Object>of("title","结果核对-"+id,"content","核对事务回执","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00");
        JsonNode task=committed?call(200,"POST","/tasks","leader",payload,Db.id()):null;
        new org.springframework.transaction.support.TransactionTemplate(transactionManager).executeWithoutResult(status->{
            db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,plan_version) VALUES (?,?,?,'RECONCILING',1)",id,company,ids.get("leader"));
            var actor=currentActors.fresh(new Actor(ids.get("leader"),company,"","","",false,false,false,"ACTIVE"));
            var plan=Map.of("sources",List.of(),"people",new cn.workpanel.module.aiwork.application.WorkPeople(db).snapshot(actor),"actions",List.of(Map.of("type","CREATE_TASK","payload",payload)));
            db.update("INSERT INTO ai_work_plans(company_id,work_id,version,body,hash,permission_fingerprint,expires_at) VALUES (?,?,1,?::jsonb,?,?,now()+interval '10 minutes')",company,id,db.write(plan),Db.hash(db.write(plan)),currentActors.fingerprint(actor));
            db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,payload,state,fence,attempts,lease_until) VALUES (?,?,?,1,'action-1','CREATE_TASK',?::jsonb,?,4,1,now()-interval '1 second')",Db.id(),company,id,db.write(payload),state);
            if(task!=null)db.update("INSERT INTO ai_action_receipts(company_id,actor_id,work_id,plan_version,step_key,request_hash,result) VALUES (?,?,?,1,'action-1',?,?::jsonb)",company,ids.get("leader"),id,mismatch?"wrong":cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,"CREATE_TASK",payload),db.write(Map.of("kind","TASK_CREATED","taskId",task.get("id").asText(),"summary","任务已创建")));
        });return id;
    }
    @Test void dependencyFailuresPropagateTransitivelyAndPreserveSuccessfulReceipts(){
        String partial=Db.id(),failed=Db.id();
        for(String id:List.of(partial,failed))db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,plan_version) VALUES (?,?,?,'EXECUTING',1)",id,company,ids.get("leader"));
        seedDependencyChain(partial);
        seedDependencyChain(failed);
        db.update("INSERT INTO ai_action_receipts(company_id,actor_id,work_id,plan_version,step_key,request_hash,result) VALUES (?,?,?,1,'action-0',?,'{\"kind\":\"TASK_CREATED\"}'::jsonb)",company,ids.get("leader"),partial,Db.hash("completed-before-failure"));

        workExecutor.propagateDependencyFailures();

        assertEquals("PARTIAL",db.one("SELECT state FROM ai_work_items WHERE id=?",partial).get("state"));
        assertEquals("FAILED",db.one("SELECT state FROM ai_work_items WHERE id=?",failed).get("state"));
        assertEquals(2,db.count("SELECT count(*) FROM ai_work_steps WHERE work_id=? AND state='FAILED' AND error_code='DEPENDENCY_FAILED'",partial));
        assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",partial));
    }
    @Test void successfulActionReceiptIsReusedOnceAndNeedsMaterialIsNeverReused(){
        String reusable=Db.id(),needsMaterial=Db.id();var payload=Map.<String,Object>of("title","重复任务","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00");
        for(String id:List.of(reusable,needsMaterial))db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,plan_version) VALUES (?,?,?,'WAITING_INPUT',2)",id,company,ids.get("leader"));
        seedReceipt(reusable,payload,"TASK_CREATED");seedReceipt(needsMaterial,payload,"NEEDS_MATERIAL");
        var actor=currentActors.fresh(new Actor(ids.get("leader"),company,"","","",false,false,false,"ACTIVE"));

        assertTrue(workRepository.completed(actor,reusable,"CREATE_TASK",payload));
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,payload) VALUES (?,?,?,2,'action-1','CREATE_TASK',?::jsonb)",Db.id(),company,reusable,db.write(payload));
        assertFalse(workRepository.completed(actor,reusable,"CREATE_TASK",payload));
        assertFalse(workRepository.completed(actor,needsMaterial,"CREATE_TASK",payload));
    }
    @RepeatedTest(20) void batchPartialSuccessRetriesOnlyUnfinishedActionAndRejectsMissingDependency()throws Exception{
        mode.set("BATCH");long before=db.count("SELECT count(*) FROM tasks WHERE company_id=?",company);
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理小李在2099年10月23日17:00交付成本表的两项任务"),Db.id()).get("id").asText();var ready=await(id,"WAITING_CONFIRMATION");
        var confirmation=new LinkedHashMap<String,Object>(Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-2")));
        assertEquals("DEPENDENCY_REQUIRED",call(400,"POST","/ai/work-items/"+id+"/confirm","leader",confirmation,Db.id()).get("code").asText());
        assertEquals(1,db.count("SELECT count(*) FROM ai_work_confirmations WHERE work_id=? AND consumed_at IS NULL",id));
        String suffix=Db.id().replace("-",""),function="it_batch_"+suffix,trigger="it_batch_trigger_"+suffix;
        db.update("CREATE FUNCTION "+function+"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.work_id='"+id+"' AND NEW.step_key='action-2' THEN RAISE EXCEPTION 'injected batch failure'; END IF; RETURN NEW; END $$");
        db.update("CREATE TRIGGER "+trigger+" BEFORE INSERT ON ai_action_receipts FOR EACH ROW EXECUTE FUNCTION "+function+"()");
        try{confirmation.put("actions",List.of("action-1","action-2"));call(200,"POST","/ai/work-items/"+id+"/confirm","leader",confirmation,Db.id());await(id,"PARTIAL");assertEquals(before+1,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));}
        finally{db.update("DROP TRIGGER "+trigger+" ON ai_action_receipts");db.update("DROP FUNCTION "+function+"()");}
        var partial=call(200,"GET","/ai/work-items/"+id,"leader",null,null);String key=Db.id();var body=Map.of("version",partial.get("version").asInt());
        for(int i=0;i<20;i++)call(200,"POST","/ai/work-items/"+id+"/retry","leader",body,key);
        var done=await(id,"SUCCEEDED");assertEquals(2,done.get("receipts").size());assertEquals(before+2,db.count("SELECT count(*) FROM tasks WHERE company_id=?",company));
        assertEquals(2,db.count("SELECT count(*) FROM audit_records WHERE type='AI_WORK_ACTION' AND object_id=?",id));
    }
    @Test void unrelatedPersonChangeDoesNotInvalidatePendingAction()throws Exception{
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理小李在2099年10月23日17:00交付成本表的任务"),Db.id()).get("id").asText();var ready=await(id,"WAITING_CONFIRMATION");
        try{db.update("UPDATE users SET name='无关人员已更名' WHERE id=?",ids.get("reviewer"));assertTrue(call(200,"GET","/ai/work-items/"+id,"leader",null,null).get("planValid").asBoolean());
            call(200,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());await(id,"SUCCEEDED");
        }finally{db.update("UPDATE users SET name='独立复核人' WHERE id=?",ids.get("reviewer"));}
    }
    @Test void finishedTargetsDoNotBlockOtherStepsButChangedPendingTargetDoes()throws Exception{
        String first=call(200,"POST","/tasks","leader",Map.of("title","已完成动作对象","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00"),Db.id()).get("id").asText();
        String second=call(200,"POST","/tasks","leader",Map.of("title","待办动作对象","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00"),Db.id()).get("id").asText();
        String id=Db.id();var actor=currentActors.fresh(new Actor(ids.get("leader"),company,"","","",false,false,false,"ACTIVE"));
        var body=Map.of("sources",List.of(),"people",new cn.workpanel.module.aiwork.application.WorkPeople(db).snapshot(actor),"actions",List.of(Map.of("type","REQUEST_RESCHEDULE","payload",Map.of("taskId",first,"taskVersion",1)),Map.of("type","REQUEST_RESCHEDULE","payload",Map.of("taskId",second,"taskVersion",1))));
        db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,plan_version) VALUES (?,?,?,'PARTIAL',1)",id,company,actor.id());
        db.update("INSERT INTO ai_work_plans(company_id,work_id,version,body,hash,permission_fingerprint,expires_at) VALUES (?,?,1,?::jsonb,'hash',?,now()+interval '10 minutes')",company,id,db.write(body),currentActors.fingerprint(actor));
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state) VALUES (?,?,?,1,'action-1','REQUEST_RESCHEDULE','SUCCEEDED')",Db.id(),company,id);
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state) VALUES (?,?,?,1,'action-2','REQUEST_RESCHEDULE','FAILED')",Db.id(),company,id);
        db.update("UPDATE tasks SET version=version+1 WHERE id=?",first);
        var plan=workRepository.plan(actor,id,1);var transaction=new org.springframework.transaction.support.TransactionTemplate(transactionManager);
        transaction.executeWithoutResult(s->workService.validateStep(actor,plan,"action-2"));
        db.update("UPDATE tasks SET version=version+1 WHERE id=?",second);
        assertThrows(ApiError.class,()->transaction.executeWithoutResult(s->workService.validateStep(actor,plan,"action-2")));
    }
    @Test void staleConfirmationCanRenewWithoutRetypingAndNeedsFreshConsent()throws Exception{
        String id=Db.id();var actor=currentActors.fresh(new Actor(ids.get("leader"),company,"","","",false,false,false,"ACTIVE"));
        db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,plan_version) VALUES (?,?,?,'WAITING_CONFIRMATION',1)",id,company,actor.id());
        db.update("INSERT INTO ai_work_messages(id,company_id,work_id,sequence,body) VALUES (?,?,?,1,?::jsonb)",Db.id(),company,id,db.write(Map.of("text","整理小李在2099年10月23日17:00交付成本表的任务")));
        db.update("INSERT INTO ai_work_plans(company_id,work_id,version,body,hash,permission_fingerprint,expires_at) VALUES (?,?,1,'{}'::jsonb,'expired-hash',?,now()-interval '1 second')",company,id,currentActors.fingerprint(actor));
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state) VALUES (?,?,?,1,'action-1','CREATE_TASK','WAITING')",Db.id(),company,id);
        var ready=call(200,"GET","/ai/work-items/"+id,"leader",null,null);
        assertFalse(call(200,"GET","/ai/work-items/"+id,"leader",null,null).get("planValid").asBoolean());
        call(200,"POST","/ai/work-items/"+id+"/retry","leader",Map.of("version",ready.get("version").asInt()),Db.id());var renewed=await(id,"WAITING_CONFIRMATION");
        assertEquals(ready.get("planVersion").asInt()+1,renewed.get("planVersion").asInt());assertNotEquals("",renewed.get("confirmationId").asText());
        assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        call(200,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",renewed.get("version").asInt(),"planVersion",renewed.get("planVersion").asInt(),"planHash",renewed.get("planHash").asText(),"confirmationId",renewed.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());assertEquals(1,await(id,"SUCCEEDED").get("receipts").size());
    }
    @Test void templateFileIsPrefilledInChildAndCannotBeReadAfterWithdrawal()throws Exception{
        byte[] bytes;try(var doc=new XWPFDocument();var out=new ByteArrayOutputStream()){doc.createParagraph().createRun().setText("{{姓名}}/{{部门}}/{{事由}}/{{审核人}}");doc.write(out);bytes=out.toByteArray();}
        String file=upload("admin",bytes,"办理模板.docx");String id=call(200,"POST","/procedures","admin",Map.of("title","文件预填模板","type","TEMPLATE","content","领取模板","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("admin"));String review=call(200,"POST","/procedures/"+id+"/publish-requests","admin",Map.of("version",1,"reason","发布"),Db.id()).get("id").asText();
        call(200,"POST","/reviews/"+review+"/decision","reviewer",Map.of("approve",true),null);
        String path="/procedures/"+id+"/template-files/"+file;
        var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).header("Authorization","Bearer "+tokens.get("alice")).header("Content-Type","application/json").POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of("version",1,"reason","领取材料")))).build(),HttpResponse.BodyHandlers.ofByteArray());
        assertEquals(200,response.statusCode(),new String(response.body(),StandardCharsets.UTF_8));assertEquals("no-store",response.headers().firstValue("cache-control").orElse(""));
        try(var doc=new XWPFDocument(new ByteArrayInputStream(response.body()))){assertEquals("小李/测试部/领取材料/{{审核人}}",doc.getParagraphs().getFirst().getText());}
        call(409,"POST",path,"alice",Map.of("version",2),null);call(404,"POST","/procedures/"+id+"/template-files/"+Db.id(),"alice",Map.of("version",1),null);call(400,"POST",path,"alice",Map.of("version",1,"role","ADMIN"),null);
        db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE id=?",id);call(404,"POST",path,"alice",Map.of("version",1),null);
    }
    @Test void maintenanceSearchPaginatesAndShowsPendingReviewWithoutPublishing()throws Exception{
        String title="维护分页"+Db.id();String first=call(200,"POST","/procedures","admin",Map.of("title",title+"甲","type","POLICY","content","维护稿"),Db.id()).get("id").asText();
        db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("admin"));
        String review=call(200,"POST","/procedures/"+first+"/publish-requests","admin",Map.of("version",1,"reason","申请发布"),Db.id()).get("id").asText();
        call(200,"POST","/procedures","admin",Map.of("title",title+"乙","type","POLICY","content","维护稿"),Db.id());
        String path="/procedures?drafts=true&search="+URLEncoder.encode(title,StandardCharsets.UTF_8)+"&limit=1&cursor=";
        var page=call(200,"GET",path+"0","admin",null,null);assertEquals(2,page.get("total").asInt());assertEquals(1,page.get("nextCursor").asInt());
        var next=call(200,"GET",path+"1","admin",null,null);assertEquals(-1,next.get("nextCursor").asInt());assertEquals(review,next.at("/items/0/pending_review_id").asText());assertEquals("PENDING",next.at("/items/0/review_status").asText());
        call(403,"GET",path+"0","alice",null,null);call(404,"GET","/procedures/"+first,"alice",null,null);
        db.update("UPDATE users SET team_id=?,department_id=? WHERE id=?",company+"-t",company+"-d",ids.get("admin"));
    }
    @Test void retentionClearsPrivateEvidenceAndOldAuditDetailsButPreservesFormalFiles()throws Exception{
        String work=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();
        var done=await(work,"SUCCEEDED");String task=done.at("/receipts/0/result/taskId").asText();
        String privateFile=Db.id(),formalFile=Db.id(),report=Db.id();
        for(String file:List.of(privateFile,formalFile)){
            db.update("INSERT INTO attachments(id,company_id,owner_id,filename,content_type,data) VALUES (?,?,?,'evidence.txt','text/plain',?::bytea)",file,company,ids.get("leader"),new byte[]{1,2,3});
            db.update("INSERT INTO attachment_bindings(company_id,attachment_id,resource_type,resource_id) VALUES (?,?,'WORK',?)",company,file,work);
        }
        db.update("UPDATE attachments SET task_id=? WHERE id=?",task,formalFile);
        db.update("INSERT INTO task_delivery_checks(id,company_id,task_id,owner_id,task_version,fingerprint,state,manifest,body,created_at) VALUES (?,?,?,?,1,'old','PASS','{}','{}',now()-interval '91 days')",report,company,task,ids.get("leader"));
        db.update("INSERT INTO task_delivery_findings(company_id,check_id,position,body) VALUES (?,?,1,'{}')",company,report);
        db.update("INSERT INTO task_delivery_check_jobs(id,company_id,task_id,owner_id,request,state,report_id,created_at) VALUES (?,?,?,?,'{}','SUCCEEDED',?,now()-interval '91 days')",Db.id(),company,task,ids.get("leader"),report);
        String marker=Db.id();db.update("INSERT INTO audit_records(company_id,actor_id,type,object_id,before_value,after_value,reason,created_at) VALUES (?,?,'AI_WORK_AUTHORIZATION',?,'{}','{\"scope\":\"private\"}','private',now()-interval '366 days')",company,ids.get("leader"),marker);
        db.update("UPDATE ai_work_items SET deleted_at=now() WHERE id=?",work);
        retention.clean();retention.clean();
        assertEquals(0,db.count("SELECT count(*) FROM ai_work_messages WHERE work_id=?",work));assertEquals(0,db.count("SELECT count(*) FROM ai_work_plans WHERE work_id=?",work));
        assertEquals(0,db.count("SELECT octet_length(data) FROM attachments WHERE id=?",privateFile));assertEquals(3,db.count("SELECT octet_length(data) FROM attachments WHERE id=?",formalFile));
        assertEquals(1,db.count("SELECT count(*) FROM tasks WHERE id=?",task));assertEquals(1,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",work));
        assertEquals(0,db.count("SELECT count(*) FROM task_delivery_checks WHERE id=?",report));
        var audit=db.one("SELECT * FROM audit_records WHERE object_id=?",marker);assertEquals(Map.of(),db.read(audit.get("after_value")));assertEquals(ids.get("leader"),audit.get("actor_id"));
        call(404,"GET","/ai/work-items/"+work,"leader",null,null);
    }
    @Test void authorizationAndRevocationAuditAreAtomicAndIdempotent()throws Exception{
        var body=Map.of("action","CREATE_TASK","scope",Map.of("ownerIds",List.of(ids.get("alice"))),"expiresAt",Instant.now().plusSeconds(3600).toString());String key=Db.id();
        String id=call(200,"POST","/ai/work-authorizations","leader",body,key).get("id").asText();call(200,"POST","/ai/work-authorizations","leader",body,key);
        String revokeKey=Db.id();for(int n=0;n<20;n++)call(200,"POST","/ai/work-authorizations/"+id+"/revoke","leader",Map.of("version",1),revokeKey);
        assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='AI_WORK_AUTHORIZATION'",id));
        assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='AI_WORK_AUTHORIZATION_REVOKED'",id));
    }
    @Test void taskTargetsComeFromTrustedInstructionOrSelectionAndAmbiguityNeverGuesses()throws Exception{
        var target=deliveryTask(true,costChecklist());var other=deliveryTask(true,costChecklist());String title="精确目标"+Db.id();String expected=target.get("id").asText();
        db.update("UPDATE tasks SET title=? WHERE id=?",title,expected);String file=word("alice","成本：10元");mode.set("OVERRIDE");sourceId.set(other.get("id").asText());
        String id=call(202,"POST","/ai/work-items","alice",Map.of("text","检查「"+title+"」的交付材料","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        var done=awaitAs(id,"SUCCEEDED","alice");assertEquals(expected,done.at("/receipts/0/result/taskId").asText());
        String unselected=call(202,"POST","/ai/work-items","alice",Map.of("text","检查交付材料","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        var ask=awaitAs(unselected,"WAITING_INPUT","alice");assertEquals(0,ask.at("/plan/actions").size());assertEquals(0,ask.get("receipts").size());
        db.update("UPDATE tasks SET title=? WHERE id=?",title,other.get("id").asText());
        String ambiguous=call(202,"POST","/ai/work-items","alice",Map.of("text","检查「"+title+"」的交付材料","attachmentIds",List.of(file)),Db.id()).get("id").asText();
        var question=awaitAs(ambiguous,"WAITING_INPUT","alice");assertTrue(question.at("/plan/questions").toString().contains("多项"));assertEquals(0,question.get("receipts").size());
        String chosen=deliveryWork(target,"alice",file,"检查交付材料");assertEquals(expected,awaitAs(chosen,"SUCCEEDED","alice").at("/receipts/0/result/taskId").asText());
    }
    private void seedDependencyChain(String id){
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,state) VALUES (?,?,?,1,'action-1','CREATE_TASK','FAILED')",Db.id(),company,id);
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,dependencies,state) VALUES (?,?,?,1,'action-2','CREATE_TASK','[\"action-1\"]'::jsonb,'PENDING')",Db.id(),company,id);
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,dependencies,state) VALUES (?,?,?,1,'action-3','CREATE_TASK','[\"action-2\"]'::jsonb,'WAITING')",Db.id(),company,id);
    }
    private void seedReceipt(String workId,Map<String,Object> payload,String kind){
        db.update("INSERT INTO ai_work_steps(id,company_id,work_id,plan_version,step_key,action,payload,state) VALUES (?,?,?,1,'action-1','CREATE_TASK',?::jsonb,'SUCCEEDED')",Db.id(),company,workId,db.write(payload));
        db.update("INSERT INTO ai_action_receipts(company_id,actor_id,work_id,plan_version,step_key,request_hash,result) VALUES (?,?,?,1,'action-1',?,?::jsonb)",company,ids.get("leader"),workId,cn.workpanel.module.aiwork.domain.WorkActions.fingerprint(db,"CREATE_TASK",payload),db.write(Map.of("kind",kind)));
    }
    @Test void changedPersonSnapshotInvalidatesConfirmationBeforeBusinessWrite()throws Exception{
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","整理小李在2099年10月23日17:00交付成本表的任务"),Db.id()).get("id").asText();var ready=await(id,"WAITING_CONFIRMATION");
        try{db.update("UPDATE users SET name='人员信息已更新' WHERE id=?",ids.get("alice"));assertFalse(call(200,"GET","/ai/work-items/"+id,"leader",null,null).get("planValid").asBoolean());
            call(409,"POST","/ai/work-items/"+id+"/confirm","leader",Map.of("version",ready.get("version").asInt(),"planVersion",ready.get("planVersion").asInt(),"planHash",ready.get("planHash").asText(),"confirmationId",ready.get("confirmationId").asText(),"actions",List.of("action-1")),Db.id());assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        }finally{db.update("UPDATE users SET name='小李' WHERE id=?",ids.get("alice"));}
    }
    @Test void changedMaterialInvalidatesReportAndStoredWorkReceipt()throws Exception{
        String task=call(200,"POST","/tasks","leader",Map.of("title","检查快照","ownerId",ids.get("alice"),"deadline","2099-10-23T17:00:00+08:00","acceptanceChecklist",List.of(Map.of("id","cost","title","成本材料","fileName","成本.docx","required",true))),Db.id()).get("id").asText();
        var bytes=new ByteArrayOutputStream();try(var doc=new XWPFDocument()){doc.createParagraph().createRun().setText("成本：10元");doc.write(bytes);}String file=upload("alice",bytes.toByteArray(),"成本.docx");
        var queued=call(202,"POST","/tasks/"+task+"/delivery-checks","alice",Map.of("taskVersion",1,"attachmentIds",List.of(file)),Db.id());JsonNode report;long until=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);do{report=call(200,"GET","/tasks/"+task+"/delivery-checks/"+queued.get("id").asText(),"alice",null,null);if(report.get("state").asText().equals("PASS"))break;Thread.sleep(100);}while(System.nanoTime()<until);assertEquals("PASS",report.get("state").asText());assertTrue(report.get("snapshotValid").asBoolean());
        String work=Db.id();var receipt=Map.of("taskId",task,"checkId",report.get("id").asText(),"report",report,"summary","材料已通过检查");db.update("INSERT INTO ai_work_items(id,company_id,owner_id,state,result) VALUES (?,?,?,'SUCCEEDED',?::jsonb)",work,company,ids.get("alice"),db.write(receipt));db.update("INSERT INTO ai_action_receipts(company_id,actor_id,work_id,plan_version,step_key,request_hash,result) VALUES (?,?,?,0,'check',?,?::jsonb)",company,ids.get("alice"),work,Db.hash("fixture"),db.write(receipt));
        db.update("UPDATE attachments SET data=? WHERE id=?","changed material".getBytes(StandardCharsets.UTF_8),file);
        var stale=call(200,"GET","/tasks/"+task+"/delivery-checks/"+report.get("id").asText(),"alice",null,null);assertEquals("STALE",stale.get("state").asText());assertEquals(0,stale.get("findings").size());
        var workView=call(200,"GET","/ai/work-items/"+work,"alice",null,null);assertEquals("STALE",workView.at("/receipts/0/result/report/state").asText());assertEquals("STALE",workView.at("/result/report/state").asText());
        boolean listed=false;for(var item:call(200,"GET","/ai/work-items","alice",null,null).get("items"))if(item.get("id").asText().equals(work)){assertEquals("STALE",item.at("/result/report/state").asText());listed=true;}assertTrue(listed);assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",task));
    }
    @Test void formalWorkflowChecklistCannotSubmitUsingWithdrawnSource()throws Exception{
        String document=call(200,"POST","/procedures","admin",Map.of("title","正式交付流程","type","PROCEDURE","content","交付必须提供报价文件","workflow","CREATE_TASK","acceptanceChecklist",List.of(Map.of("title","报价文件","fileName","报价.docx","required",true))),Db.id()).get("id").asText();
        db.update("UPDATE users SET department_id=NULL,team_id=NULL WHERE id=?",ids.get("admin"));var publication=call(200,"POST","/procedures/"+document+"/publish-requests","admin",Map.of("version",1,"reason","正式发布"),Db.id());call(200,"POST","/reviews/"+publication.get("id").asText()+"/decision","reviewer",Map.of("approve",true,"reason","通过"),null);
        sourceId.set(document);String work=call(202,"POST","/ai/work-items","leader",Map.of("text","请帮我创建任务：小李在2099年10月23日17:00交付成本表"),Db.id()).get("id").asText();var done=await(work,"SUCCEEDED");String task=done.at("/receipts/0/result/taskId").asText();var checklist=call(200,"GET","/tasks/"+task,"alice",null,null).at("/fields/acceptanceChecklist");assertTrue(checklist.toString().contains("procedure:"+document+"@1"));
        int version=call(200,"GET","/tasks/"+task,"alice",null,null).get("version").asInt();var accepted=call(200,"POST","/tasks/"+task+"/events","alice",Map.of("version",version,"type","RECEIVED","text","开始准备"),null);version=accepted.get("version").asInt();
        var bytes=new ByteArrayOutputStream();try(var doc=new XWPFDocument()){doc.createParagraph().createRun().setText("报价：10元");doc.write(bytes);}String file=upload("alice",bytes.toByteArray(),"报价.docx");var job=call(202,"POST","/tasks/"+task+"/delivery-checks","alice",Map.of("taskVersion",version,"attachmentIds",List.of(file)),Db.id());JsonNode report;long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);do{report=call(200,"GET","/tasks/"+task+"/delivery-checks/"+job.get("id").asText(),"alice",null,null);if(report.get("state").asText().equals("PASS"))break;Thread.sleep(100);}while(System.nanoTime()<end);assertEquals("PASS",report.get("state").asText());
        var withdrawal=call(200,"POST","/procedures/"+document+"/publish-requests","admin",Map.of("version",2,"reason","撤回流程","withdraw",true),Db.id());call(200,"POST","/reviews/"+withdrawal.get("id").asText()+"/decision","reviewer",Map.of("approve",true,"reason","同意"),null);
        var stale=call(200,"GET","/tasks/"+task+"/delivery-checks/"+job.get("id").asText(),"alice",null,null);assertEquals("STALE",stale.get("state").asText());assertFalse(stale.get("snapshotValid").asBoolean());assertEquals(0,stale.get("findings").size());
        call(404,"POST","/tasks/"+task+"/deliveries","alice",Map.of("taskVersion",version,"checkId",report.get("id").asText(),"checkVersion",report.get("version").asInt(),"attachmentIds",List.of(file),"mode","CHECKED","text","请验收"),Db.id());assertEquals(0,db.count("SELECT count(*) FROM task_deliveries WHERE task_id=?",task));
    }
    /** 真 HTTP 流读取有界等待，EOF/异常可见，关闭连接不遗留测试线程。 */
    final class SseProbe implements AutoCloseable {
        final InputStream body;final BlockingQueue<Map<String,String>> events=new LinkedBlockingQueue<>();
        SseProbe(String id,String who,String cursor)throws Exception{
            var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/ai/work-items/"+id+"/stream")).timeout(Duration.ofSeconds(10)).header("Authorization","Bearer "+tokens.get(who)).header("Last-Event-ID",cursor).header("Accept","text/event-stream").build(),HttpResponse.BodyHandlers.ofInputStream());
            assertEquals(200,response.statusCode());body=response.body();
            Thread reader=new Thread(()->{try(var lines=new BufferedReader(new InputStreamReader(body,StandardCharsets.UTF_8))){Map<String,String> event=new HashMap<>();String line;while((line=lines.readLine())!=null){if(line.isEmpty()){if(event.containsKey("data"))events.add(Map.copyOf(event));event.clear();}else if(!line.startsWith(":")){int c=line.indexOf(':');if(c>0)event.put(line.substring(0,c),line.substring(c+1).stripLeading());}}}catch(IOException ignored){}finally{events.add(Map.of("event","eof"));}},"work-sse-test");reader.setDaemon(true);reader.start();
        }
        Map<String,String> next(String type)throws Exception{long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);while(System.nanoTime()<deadline){var event=events.poll(Math.max(1,TimeUnit.NANOSECONDS.toMillis(deadline-System.nanoTime())),TimeUnit.MILLISECONDS);if(event==null)break;if(type.equals(event.get("event")))return event;if("eof".equals(event.get("event")))fail("Stream ended before "+type);}fail("No SSE "+type);return Map.of();}
        @Override public void close()throws IOException{body.close();}
    }
    String questionWork(String who)throws Exception{mode.set("QUESTION");String id=call(202,"POST","/ai/work-items",who,Map.of("text","请整理交付要求"),Db.id()).get("id").asText();awaitAs(id,"WAITING_INPUT",who);return id;}
    void streamStatus(int status,String work,String who,String cursor)throws Exception{
        var result=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/ai/work-items/"+work+"/stream")).timeout(Duration.ofSeconds(8)).header("Authorization","Bearer "+tokens.get(who)).header("Last-Event-ID",cursor).build(),HttpResponse.BodyHandlers.ofString());assertEquals(status,result.statusCode(),result.body());
    }
    @Test void sseReplaysDurableOrderAndReconnectsWithoutRepeatingEffects()throws Exception{
        user("stream-replay","EMPLOYEE","恢复测试",false,false);String id=questionWork("stream-replay");
        var persisted=db.rows("SELECT sequence,version FROM ai_work_events WHERE work_id=? ORDER BY sequence",id);long last=0;
        try(var stream=new SseProbe(id,"stream-replay","0")){
            for(var row:persisted){var event=stream.next("change");long sequence=Long.parseLong(event.get("id"));assertTrue(sequence>last);last=sequence;assertEquals(row.get("sequence").toString(),event.get("id"));var data=JSON.readTree(event.get("data"));assertEquals(1,data.size());assertEquals(((Number)row.get("version")).intValue(),data.get("version").asInt());}
        }
        var before=call(200,"GET","/ai/work-items/"+id,"stream-replay",null,null);assertEquals(last,before.get("eventsCursor").asLong());
        try(var stream=new SseProbe(id,"stream-replay",String.valueOf(last))){
            call(200,"POST","/ai/work-items/"+id+"/messages","stream-replay",Map.of("version",before.get("version").asInt(),"text","补充交付材料"),Db.id());
            assertTrue(Long.parseLong(stream.next("change").get("id"))>last);
        }
        awaitAs(id,"WAITING_INPUT","stream-replay");assertEquals(0,db.count("SELECT count(*) FROM ai_action_receipts WHERE work_id=?",id));
        streamStatus(400,id,"stream-replay","-1");streamStatus(400,id,"stream-replay","wrong");streamStatus(400,id,"stream-replay","9223372036854775808");streamStatus(400,id,"stream-replay",String.valueOf(db.count("SELECT max(sequence)+1 FROM ai_work_events WHERE work_id=?",id)));
        streamStatus(404,id,"admin","0");
    }
    @Test void streamStopsAndSendsNoPrivateBodyAfterMembershipSessionOrDeletionLoss()throws Exception{
        for(String loss:List.of("membership","session","deletion")){
            String who="stream-"+loss;user(who,"EMPLOYEE","隐私测试",false,false);String id=questionWork(who);var item=call(200,"GET","/ai/work-items/"+id,who,null,null);
            try(var stream=new SseProbe(id,who,item.get("eventsCursor").asText())){
                int status;
                if(loss.equals("membership")){db.update("UPDATE users SET status='PENDING' WHERE id=?",ids.get(who));status=403;}
                else if(loss.equals("session")){db.update("DELETE FROM sessions WHERE user_id=?",ids.get(who));status=401;}
                else{var response=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/ai/work-items/"+id)).header("Authorization","Bearer "+tokens.get(who)).header("If-Match",item.get("version").asText()).header("Idempotency-Key",Db.id()).DELETE().build(),HttpResponse.BodyHandlers.ofString());assertEquals(202,response.statusCode());status=404;}
                var event=stream.next("access-lost");assertNull(event.get("id"));assertEquals(Map.of("status",status),JSON.convertValue(JSON.readTree(event.get("data")),Map.class));stream.next("eof");call(status,"GET","/ai/work-items/"+id,who,null,null);
            }
        }
    }
    @Test void sourceRevocationRefreshesSameVersionWithoutPrivateContent()throws Exception{
        user("stream-source","EMPLOYEE","来源测试",false,false);String document=published("差旅办法","差旅报销需要行程单","COMPANY",null);mode.set("KNOWLEDGE");sourceId.set(document);
        String id=call(202,"POST","/ai/work-items","stream-source",Map.of("text","查差旅报销办法"),Db.id()).get("id").asText();var item=awaitAs(id,"SUCCEEDED","stream-source");assertTrue(item.get("planValid").asBoolean());
        try(var stream=new SseProbe(id,"stream-source",item.get("eventsCursor").asText())){
            db.update("UPDATE procedure_documents SET state='WITHDRAWN' WHERE id=?",document);var event=stream.next("refresh");assertNull(event.get("id"));assertEquals(item.get("version").asInt(),JSON.readTree(event.get("data")).get("version").asInt());assertFalse(event.get("data").contains("差旅"));
            var next=call(200,"GET","/ai/work-items/"+id,"stream-source",null,null);assertEquals(item.get("version"),next.get("version"));assertEquals(item.get("eventsCursor"),next.get("eventsCursor"));assertFalse(next.get("planValid").asBoolean());assertFalse(next.has("plan"));
        }
    }
    @Test void concurrentGetVersionAndCursorUseOneSnapshot()throws Exception{
        user("stream-snapshot","EMPLOYEE","快照测试",false,false);String id=questionWork("stream-snapshot");Actor a=Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("stream-snapshot")));var tx=new org.springframework.transaction.support.TransactionTemplate(transactionManager);var repo=new cn.workpanel.module.aiwork.infrastructure.WorkRepository(db);
        var writer=CompletableFuture.runAsync(()->{for(int n=0;n<60;n++){tx.executeWithoutResult(s->repo.state(a,id,"WAITING_INPUT",Map.of("summary","快照更新")));try{Thread.sleep(10);}catch(InterruptedException e){Thread.currentThread().interrupt();return;}}});
        try{for(int n=0;n<24;n++){var view=call(200,"GET","/ai/work-items/"+id,"stream-snapshot",null,null);var event=db.one("SELECT version FROM ai_work_events WHERE work_id=? AND sequence=?",id,view.get("eventsCursor").asLong());assertEquals(((Number)event.get("version")).intValue(),view.get("version").asInt());}}finally{writer.get(10,TimeUnit.SECONDS);}
    }
    @Test void actionableNotificationsAreAtomicAndTwentyReplaysDeduplicate()throws Exception{
        user("stream-notice","EMPLOYEE","通知测试",false,false);String id=questionWork("stream-notice");Actor a=Actor.from(db.one("SELECT * FROM users WHERE id=?",ids.get("stream-notice")));var tx=new org.springframework.transaction.support.TransactionTemplate(transactionManager);var repo=new cn.workpanel.module.aiwork.infrastructure.WorkRepository(db);
        long initial=db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id);assertEquals(1,initial);
        for(String state:List.of("PREPARING","EXECUTING","WAITING_REVIEW"))tx.executeWithoutResult(s->repo.state(a,id,state,Map.of()));assertEquals(initial,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
        tx.executeWithoutResult(s->repo.state(a,id,"WAITING_INPUT",Map.of()));tx.executeWithoutResult(s->repo.state(a,id,"WAITING_INPUT",Map.of()));assertEquals(initial+1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
        assertThrows(IllegalStateException.class,()->tx.executeWithoutResult(s->{repo.state(a,id,"SUCCEEDED",Map.of());throw new IllegalStateException("rollback");}));assertEquals(initial+1,db.count("SELECT count(*) FROM outbox_events WHERE object_id=?",id));
        var messages=new cn.workpanel.module.message.application.MessageApplicationService(db,true);
        for(int n=0;n<20;n++){db.update("UPDATE outbox_events SET delivered_at=NULL WHERE object_id=?",id);tx.executeWithoutResult(s->messages.deliver());}
        assertEquals(initial+1,db.count("SELECT count(*) FROM notifications WHERE object_id=?",id));assertEquals(0,db.count("SELECT count(*) FROM outbox_events WHERE object_id=? AND delivered_at IS NULL",id));
    }
    @Test void privateWorkFileReportAndCacheRejectManagersOutsideScopesAndOtherCompany()throws Exception{
        user("outside-scope","LEADER","外组负责人",true,false);db.update("UPDATE users SET team_id=NULL,department_id=NULL WHERE id=?",ids.get("outside-scope"));
        String other=company+"-other",foreign=Db.id(),token=Db.id();db.update("INSERT INTO companies(id,name) VALUES (?,?)",other,"其他公司");db.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,role,status,dispatch_enabled,company_reviewer) VALUES (?,?,?,?,?,?,'ADMIN','ACTIVE',true,true)",foreign,other,foreign,"x",foreign,"其他公司管理员");db.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(token),foreign);ids.put("foreign-admin",foreign);tokens.put("foreign-admin",token);
        byte[] png=Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII=");String file=upload("alice",png,"私人截图.png");mode.set("QUESTION");String work=call(202,"POST","/ai/work-items","alice",Map.of("text","私人事项隐私标记","attachmentIds",List.of(file)),Db.id()).get("id").asText();awaitAs(work,"WAITING_INPUT","alice");assertEquals(1,db.count("SELECT count(*) FROM ai_file_extractions WHERE attachment_id=? AND owner_id=?",file,ids.get("alice")));
        var task=deliveryTask(true,List.of(Map.of("title","提供材料","fileName","成本.docx","required",true)));String taskId=task.get("id").asText(),material=word("alice","私人材料内容");var job=call(202,"POST","/tasks/"+taskId+"/delivery-checks","alice",Map.of("taskVersion",2,"attachmentIds",List.of(material)),Db.id());var report=awaitCheck(taskId,job.get("id").asText());assertEquals("PASS",report.get("state").asText());
        for(String who:List.of("leader","admin","outside-scope","foreign-admin")){
            call(404,"GET","/ai/work-items/"+work,who,null,null);streamStatus(404,work,who,"0");call(404,"POST","/ai/work-items/"+work+"/messages",who,Map.of("version",1,"text","替他人继续办理"),Db.id());call(404,"POST","/ai/work-items/"+work+"/cancel",who,Map.of("version",1),Db.id());assertFalse(call(200,"GET","/ai/work-items",who,null,null).toString().contains(work));
            call(who.equals("foreign-admin")?404:403,"GET","/attachments/"+file,who,null,null);
            call(who.equals("foreign-admin")?404:403,"POST","/ai/work-items",who,Map.of("text","读取这份材料","attachmentIds",List.of(file)),Db.id());
            call(404,"GET","/tasks/"+taskId+"/delivery-checks/"+report.get("id").asText(),who,null,null);
        }
        assertEquals(1,db.count("SELECT count(*) FROM ai_file_extractions WHERE attachment_id=?",file));assertEquals(0,db.count("SELECT count(*) FROM ai_work_items WHERE company_id=? AND owner_id=?",other,foreign));
    }
    @Test @org.junit.jupiter.api.extension.ExtendWith(org.springframework.boot.test.system.OutputCaptureExtension.class)
    void pendingDisabledAndOutOfScopeMembersCannotSearchDownloadOrReachAiContext(org.springframework.boot.test.system.CapturedOutput output)throws Exception{
        user("inactive-probe","EMPLOYEE","受限账号",false,false);String who="inactive-probe",file=word("alice","受保护下载");
        String draft=call(200,"POST","/procedures","admin",Map.of("title","私有制度标记","type","POLICY","content","此草稿不得外传"),Db.id()).get("id").asText();
        for(String status:List.of("PENDING","DISABLED"))try{
            db.update("UPDATE users SET status=? WHERE id=?",status,ids.get(who));int denied=status.equals("PENDING")?403:401;String before=input.get();
            for(String path:List.of("/ai/work-capabilities","/ai/work-items","/procedures?search=private","/procedures/"+draft,"/attachments/"+file,"/ai/work-authorization-options?action=CHECK_DELIVERY"))call(denied,"GET",path,who,null,null);
            call(denied,"POST","/ai/work-items",who,Map.of("text","读取公司资料"),Db.id());assertEquals(before,input.get());
        }finally{db.update("UPDATE users SET status='ACTIVE' WHERE id=?",ids.get(who));}
        call(404,"GET","/procedures/"+draft,"alice",null,null);assertEquals(0,call(200,"GET","/procedures?search="+URLEncoder.encode("私有制度标记",StandardCharsets.UTF_8),"alice",null,null).get("total").asInt());
        String department=company+"-private-dept";db.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",department,company,"未授权部门");String restricted=published("隐藏制度","隐藏部门保密内容","DEPARTMENT",department);call(404,"GET","/procedures/"+restricted,"leader",null,null);assertEquals(0,call(200,"GET","/procedures?search="+URLEncoder.encode("隐藏制度",StandardCharsets.UTF_8),"leader",null,null).get("total").asInt());
        mode.set("QUESTION");String noteTask=deliveryTask(false,List.of()).get("id").asText();call(200,"PUT","/private-notes","leader",Map.of("resource","tasks","objectId",noteTask,"text","never-disclose-private-note","version",0),null);
        call(200,"PUT","/logs/draft","leader",Map.of("businessDate",LocalDate.now().toString(),"version",0,"body",Map.of("work","never-disclose-unsubmitted-diary")),null);
        String id=call(202,"POST","/ai/work-items","leader",Map.of("text","请整理联系手机号13800138000的信息"),Db.id()).get("id").asText();await(id,"WAITING_INPUT");assertFalse(input.get().contains("13800138000"));assertFalse(input.get().contains("never-disclose-private-note"));assertFalse(input.get().contains("never-disclose-unsubmitted-diary"));assertFalse(input.get().contains("此草稿不得外传"));assertFalse(input.get().contains("隐藏部门保密内容"));assertFalse(output.getAll().contains("13800138000"));assertFalse(output.getAll().contains("never-disclose-private-note"));assertFalse(output.getAll().contains("never-disclose-unsubmitted-diary"));
    }

}
