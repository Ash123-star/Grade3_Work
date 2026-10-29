package cn.workpanel.module.task;

import cn.workpanel.Db;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

/**
 * 任务派发：真实 PostgreSQL/Redis + HTTP。组织夹具直接写库（每次运行使用独立公司 ID），
 * 业务操作全部经由 HTTP 接口。
 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT, properties={
    // 与全仓端到端测试复用同一个临时数据库时，必须采用同一初始管理员，避免测试顺序导致登录夹具不一致。
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001", "app.deepseek-key=local-mock-only", "app.jobs-enabled=false"
})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class TaskDispatchIntegrationTest {
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired JdbcTemplate jdbc;
    @Autowired StringRedisTemplate redis;
    static final ObjectMapper JSON=new ObjectMapper();
    final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    final String run=UUID.randomUUID().toString().substring(0,8);
    final String company="it-"+run, other="it-other-"+run;
    final Map<String,String> token=new HashMap<>(), id=new HashMap<>();
    final String deadline=LocalDate.now(ZoneId.of("Asia/Shanghai")).plusDays(3).atTime(18,0).atZone(ZoneId.of("Asia/Shanghai")).toOffsetDateTime().toString();

    // ---- 夹具 ----
    @BeforeAll void fixtures() {
        redis.delete(redis.keys("workpanel:api:*"));
        for(String c:List.of(company,other)) {
            jdbc.update("INSERT INTO companies(id,name) VALUES (?,?)",c,"测试公司"+c);
            jdbc.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?),(?,?,?)",c+"-d1",c,"研发部",c+"-d2",c,"市场部");
            jdbc.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?),(?,?,?,?)",c+"-t1",c,c+"-d1","研发一组",c+"-t2",c,c+"-d1","研发二组");
        }
        user("leader",company,"LEADER","d1","t1","ACTIVE",true);
        user("founder",company,"FOUNDER",null,null,"ACTIVE",true);
        user("leader2",company,"LEADER","d1","t2","ACTIVE",true);
        user("director",company,"DIRECTOR","d1",null,"ACTIVE",true);
        user("alice",company,"EMPLOYEE","d1","t1","ACTIVE",false);
        user("amy",company,"EMPLOYEE","d1","t1","ACTIVE",false);
        user("carl",company,"EMPLOYEE","d1","t2","ACTIVE",false);
        user("mia",company,"EMPLOYEE","d2",null,"ACTIVE",false);
        user("pending",company,"EMPLOYEE","d1","t1","PENDING",false);
        user("disabled",company,"EMPLOYEE","d1","t1","DISABLED",false);
        user("muted",company,"LEADER","d1","t1","ACTIVE",false);
        user("reviewer",company,"EMPLOYEE","d1","t1","ACTIVE",false);
        user("outsider",other,"LEADER","d1","t1","ACTIVE",true);
        // 专用转派/改期申请由公司复核人最终生效；日志修订还会经过直属团队和部门复核。
        jdbc.update("UPDATE users SET company_reviewer=true WHERE id=?",id.get("reviewer"));
        for(String applicant:List.of("leader","leader2","director"))
            jdbc.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)",id.get(applicant),id.get("reviewer"),company);
    }

    /** 每个 HTTP 场景独立计数，避免测试数量增加后误触发生产限流器。 */
    @BeforeEach void resetApiRateLimits() { redis.delete(redis.keys("workpanel:api:*")); }

    void user(String who,String c,String role,String dept,String team,String status,boolean dispatch) {
        String uid=c+"-"+who; id.put(who,uid);
        jdbc.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            uid,c,uid,"x","p-"+uid,who,dept==null?null:c+"-"+dept,team==null?null:c+"-"+team,role,status,dispatch);
        String t=UUID.randomUUID().toString(); token.put(who,t);
        jdbc.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(t),uid);
    }

    // ---- HTTP ----
    HttpResponse<String> send(String method,String path,String who,Object body,String key) throws Exception {
        var b=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).timeout(Duration.ofSeconds(15));
        if(who!=null) b.header("Authorization","Bearer "+token.get(who));
        if(key!=null) b.header("Idempotency-Key",key);
        if(body!=null) b.header("Content-Type","application/json");
        return http.send(b.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body))).build(),HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    }
    JsonNode call(int status,String method,String path,String who,Object body,String key) throws Exception {
        var r=send(method,path,who,body,key); assertEquals(status,r.statusCode(),method+" "+path+" "+r.body()); return JSON.readTree(r.body());
    }
    JsonNode requestTask(String who,Map<String,Object> body,String key) throws Exception { return call(200,"POST","/tasks",who,body,key); }
    JsonNode dispatch(String who,Map<String,Object> body,String key) throws Exception {
        var request=requestTask(who,body,key);
        approveTaskRevision(request.get("id").asText());
        return call(200,"GET","/tasks/"+request.get("target_id").asText(),who,null,null);
    }
    String error(int status,String who,Map<String,Object> body,String key) throws Exception { return call(status,"POST","/tasks",who,body,key).get("code").asText(); }
    String key() { return "k-"+UUID.randomUUID(); }

    Map<String,Object> body(String title,String owner,String... collaborators) {
        var participants=new ArrayList<String>(); participants.add(id.get(owner));
        Arrays.stream(collaborators).map(id::get).forEach(participants::add);
        var m=new LinkedHashMap<String,Object>(); m.put("title",title); m.put("participants",participants); m.put("deadline",deadline); m.put("content","任务内容");
        return m;
    }
    String upload(String who) throws Exception {
        String boundary="it-"+run; String part="--"+boundary+"\r\nContent-Disposition: form-data; name=\"file\"; filename=\"spec.txt\"\r\nContent-Type: text/plain\r\n\r\nfile-of-"+who+"\r\n--"+boundary+"--\r\n";
        var r=http.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api/attachments")).header("Authorization","Bearer "+token.get(who)).header("Content-Type","multipart/form-data; boundary="+boundary).POST(HttpRequest.BodyPublishers.ofString(part)).build(),HttpResponse.BodyHandlers.ofString());
        assertEquals(200,r.statusCode(),r.body()); return JSON.readTree(r.body()).get("id").asText();
    }
    long count(String sql,Object... args) { return db.count(sql,args); }
    long companyTasks() { return count("SELECT count(*) FROM tasks WHERE company_id=?",company); }
    void event(String taskId,String who,String type,int version,String text) throws Exception {
        var b=new LinkedHashMap<String,Object>(Map.of("type",type,"version",version)); if(text!=null) b.put("text",text); call(200,"POST","/tasks/"+taskId+"/events",who,b,null);
    }
    int version(String taskId,String who) throws Exception { return call(200,"GET","/tasks/"+taskId,who,null,null).get("version").asInt(); }

    JsonNode list(int status,String query,String who) throws Exception { return call(status,"GET","/tasks?"+query,who,null,null); }

    @Test void taskCreateIsInvisibleUntilReviewApproval() throws Exception {
        var request=requestTask("leader",body("待审核创建","alice"),key());
        assertEquals("TASK_CREATE",request.get("kind").asText());
        String taskId=request.get("target_id").asText();
        call(404,"GET","/tasks/"+taskId,"leader",null,null);
        approveTaskRevision(request.get("id").asText());
        assertEquals(taskId,call(200,"GET","/tasks/"+taskId,"alice",null,null).get("id").asText());
    }

    /** 任务列表只使用白名单投影，不因不同生命周期泄露状态、完成或正文。 */
    @Test void taskListUsesSafeProjectionAndOrganizationScope() throws Exception {
        String prefix="list-safe-"+UUID.randomUUID();
        String alice=dispatch("leader",body(prefix+"-alice","alice"),key()).get("id").asText();
        String amy=dispatch("leader",body(prefix+"-amy","amy"),key()).get("id").asText();
        event(alice,"alice","RECEIVED",1,null);
        var leaderPage=list(200,"search="+prefix+"&limit=10","leader");
        assertEquals(2,leaderPage.get("total").asInt());
        assertEquals(Set.of(alice,amy),Set.of(leaderPage.get("items").get(0).get("id").asText(),leaderPage.get("items").get(1).get("id").asText()));
        Set<String> allowed=Set.of("id","issuer_id","title","start_at","deadline","version","created_at","participants","label");
        for(JsonNode item:leaderPage.get("items")) {
            var names=new HashSet<String>(); item.fieldNames().forEachRemaining(names::add);
            assertEquals(allowed,names);
            for(String hidden:List.of("phase","status","completion","progress","done","accepted","archived","withdrawn","body","events")) assertFalse(item.has(hidden),hidden);
        }
        var alicePage=list(200,"search="+prefix+"&limit=10","alice");
        assertEquals(1,alicePage.get("total").asInt()); assertEquals(alice,alicePage.get("items").get(0).get("id").asText());
    }

    /** 越权负责人筛选和分页同样不能成为任务存在性探测通道。 */
    @Test void taskListRejectsOutOfScopeOwnerAndPaginatesVisibleTasks() throws Exception {
        String prefix="list-page-"+UUID.randomUUID();
        dispatch("leader",body(prefix+"-one","alice"),key()); dispatch("leader",body(prefix+"-two","amy"),key());
        var first=list(200,"search="+prefix+"&limit=1&cursor=0","leader");
        var second=list(200,"search="+prefix+"&limit=1&cursor=1","leader");
        assertEquals(2,first.get("total").asInt()); assertEquals(2,second.get("total").asInt());
        assertNotEquals(first.get("items").get(0).get("id").asText(),second.get("items").get(0).get("id").asText());
        assertEquals("1",first.get("nextCursor").asText());
        var forbidden=list(403,"participantId="+id.get("carl"),"leader"); assertEquals("FORBIDDEN",forbidden.get("code").asText()); assertFalse(forbidden.has("items"));
        var hidden=list(404,"participantId="+id.get("outsider"),"leader"); assertEquals("NOT_FOUND",hidden.get("code").asText()); assertFalse(hidden.has("items"));
        var invalid=list(400,"date=not-a-date","leader"); assertEquals("INVALID_DATE",invalid.get("code").asText()); assertFalse(invalid.has("items"));
    }
    // 6.1 正常生命周期与时间线
    @Test void lifecycleTimeline() throws Exception {
        var created=dispatch("leader",body("生命周期任务","alice","amy"),key()); String t=created.get("id").asText();
        assertEquals(1,created.get("version").asInt()); assertEquals("DISPATCHED",db.one("SELECT phase FROM tasks WHERE id=?",t).get("phase"));
        var first=created.get("events").get(0);
        assertTrue(first.get("from_phase").isNull()); assertEquals("DISPATCHED",first.get("to_phase").asText()); assertEquals(1,first.get("task_version").asInt());
        event(t,"alice","RECEIVED",1,null); event(t,"amy","FEEDBACK",2,"协作反馈"); event(t,"leader","RETURNED",3,"请补充依据"); event(t,"alice","FEEDBACK",4,"补充完成"); event(t,"leader","ACCEPTED",5,null); event(t,"leader","ARCHIVED",6,null);
        var events=call(200,"GET","/tasks/"+t,"alice",null,null).get("events");
        assertEquals(List.of("DISPATCHED","RECEIVED","FEEDBACK","RETURNED","FEEDBACK","ACCEPTED","ARCHIVED"),events.findValuesAsText("type"));
        assertEquals(first,events.get(0)); assertEquals(id.get("leader"),events.get(0).get("actor_id").asText());
        long prev=-1; for(int i=0;i<events.size();i++) { var e=events.get(i); assertTrue(e.get("sequence").asLong()>prev); prev=e.get("sequence").asLong(); assertEquals(i+1,e.get("task_version").asInt()); }
        assertEquals("FEEDBACK",events.get(3).get("from_phase").asText()); assertEquals("RECEIVED",events.get(3).get("to_phase").asText());
        assertEquals("INVALID_TRANSITION",call(409,"POST","/tasks/"+t+"/events","leader",Map.of("type","WITHDRAWN","version",7,"text","终态撤回"),null).get("code").asText());
        assertEquals("INVALID_TRANSITION",call(409,"POST","/tasks/"+t+"/reassignments","leader",Map.of("ownerId",id.get("amy"),"version",7,"reason","终态转派"),null).get("code").asText());
        assertEquals("INVALID_TRANSITION",call(409,"POST","/tasks/"+t+"/reschedules","leader",Map.of("deadline",deadline,"version",7,"reason","终态改期"),null).get("code").asText());
    }

    /** 非法状态、越权、未知动作和旧版本均不可改变任务或追加时间线。 */
    @Test void lifecycleRejectsInvalidTransitionsVersionsAndUnauthorizedActors() throws Exception {
        String t=dispatch("leader",body("生命周期拒绝","alice","amy"),key()).get("id").asText();
        assertEquals("INVALID_TRANSITION",call(409,"POST","/tasks/"+t+"/events","alice",Map.of("type","FEEDBACK","version",1,"text","跳过接收"),null).get("code").asText());
        event(t,"amy","RECEIVED",1,null);
        assertEquals("INVALID_EVENT",call(400,"POST","/tasks/"+t+"/events","alice",Map.of("type","UNKNOWN","version",1),null).get("code").asText());
        assertEquals("FORBIDDEN",call(403,"POST","/tasks/"+t+"/events","director",Map.of("type","ACCEPTED","version",2),null).get("code").asText());
        assertEquals("FORBIDDEN",call(403,"POST","/tasks/"+t+"/events","alice",Map.of("type","ACCEPTED","version",2),null).get("code").asText());
        assertEquals("NOT_FOUND",call(404,"POST","/tasks/"+t+"/events","leader2",Map.of("type","RECEIVED","version",2),null).get("code").asText());
        assertEquals("INVALID_FIELD",call(400,"POST","/tasks/"+t+"/events","alice",Map.of("type","FEEDBACK","version",2),null).get("code").asText());
        assertEquals("INVALID_VERSION",call(400,"POST","/tasks/"+t+"/events","alice",Map.of("type","FEEDBACK","text","缺版本"),null).get("code").asText());
        event(t,"amy","FEEDBACK",2,"协作成果");
        assertEquals("VERSION_CONFLICT",call(409,"POST","/tasks/"+t+"/events","leader",Map.of("type","ACCEPTED","version",2),null).get("code").asText());
        assertEquals(3,count("SELECT count(*) FROM task_events WHERE task_id=?",t));
        assertEquals("FEEDBACK",db.one("SELECT phase FROM tasks WHERE id=?",t).get("phase"));
    }

    /** 相同版本的并发反馈/撤回只能有一方提交成功，另一方必须返回版本冲突。 */
    @Test void concurrentLifecycleActionsAllowExactlyOneWriter() throws Exception {
        String t=dispatch("leader",body("并发生命周期","alice"),key()).get("id").asText();
        event(t,"alice","RECEIVED",1,null);
        var pool=Executors.newFixedThreadPool(2);
        try {
            var feedback=pool.submit(()->send("POST","/tasks/"+t+"/events","alice",Map.of("type","FEEDBACK","version",2,"text","并发反馈"),null));
            var withdrawal=pool.submit(()->send("POST","/tasks/"+t+"/events","leader",Map.of("type","WITHDRAWN","version",2,"text","并发撤回"),null));
            var statuses=List.of(feedback.get(20,TimeUnit.SECONDS).statusCode(),withdrawal.get(20,TimeUnit.SECONDS).statusCode());
            assertEquals(1,statuses.stream().filter(code->code==200).count());
            assertEquals(1,statuses.stream().filter(code->code==409).count());
            assertEquals(3,count("SELECT count(*) FROM task_events WHERE task_id=?",t));
            assertEquals(3,((Number)db.one("SELECT version FROM tasks WHERE id=?",t).get("version")).intValue());
        } finally { pool.shutdownNow(); }
    }

    /** 事件插入失败时，生命周期更新与版本增加必须在同一事务中回滚。 */
    @Test void lifecycleEventInsertFailureRollsBackTaskUpdate() throws Exception {
        String t=dispatch("leader",body("事件失败回滚","alice"),key()).get("id").asText();
        String function="reject_task_event_"+UUID.randomUUID().toString().replace("-","");
        String trigger="reject_task_event_trigger_"+UUID.randomUUID().toString().replace("-","");
        jdbc.execute("CREATE FUNCTION "+function+"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test task event failure'; END; $$");
        jdbc.execute("CREATE TRIGGER "+trigger+" BEFORE INSERT ON task_events FOR EACH ROW WHEN (NEW.task_id = '"+t+"') EXECUTE FUNCTION "+function+"()");
        try {
            var response=send("POST","/tasks/"+t+"/events","alice",Map.of("type","RECEIVED","version",1),null);
            assertTrue(response.statusCode()>=400,response.body());
        } finally {
            jdbc.execute("DROP TRIGGER IF EXISTS "+trigger+" ON task_events");
            jdbc.execute("DROP FUNCTION IF EXISTS "+function+"()");
        }
        var task=db.one("SELECT phase,version FROM tasks WHERE id=?",t);
        assertEquals("DISPATCHED",task.get("phase")); assertEquals(1,((Number)task.get("version")).intValue());
        assertEquals(1,count("SELECT count(*) FROM task_events WHERE task_id=?",t));
    }

    // 1.2 / 时间线篡改被数据库拒绝
    @Test void timelineAppendOnly() throws Exception {
        String t=dispatch("leader",body("只追加","alice"),key()).get("id").asText();
        String before=JSON.writeValueAsString(call(200,"GET","/tasks/"+t,"alice",null,null).get("events"));
        assertThrows(Exception.class,()->jdbc.update("UPDATE task_events SET type='ACCEPTED' WHERE task_id=?",t));
        assertThrows(Exception.class,()->jdbc.update("DELETE FROM task_events WHERE task_id=?",t));
        assertThrows(Exception.class,()->jdbc.execute("TRUNCATE task_events CASCADE"));
        assertEquals(before,JSON.writeValueAsString(call(200,"GET","/tasks/"+t,"alice",null,null).get("events")));
    }

    // 6.2 幂等
    @Test void replaySameAndReordered() throws Exception {
        String k=key(); var b=body("重放任务","alice","amy","leader"); String a1=upload("leader"),a2=upload("leader"); b.put("attachments",List.of(a1,a2));
        String t=dispatch("leader",b,k).get("id").asText(); long tasks=companyTasks();
        var reordered=body("重放任务","alice"); reordered.put("participants",List.of(id.get("leader"),id.get("amy"),id.get("amy"),id.get("alice"))); reordered.put("attachments",List.of(a2,a1,a2)); reordered.put("urgency","NORMAL");
        assertEquals(t,dispatch("leader",reordered,k).get("id").asText());
        assertEquals(t,dispatch("leader",b,k).get("id").asText());
        assertEquals(tasks,companyTasks()); assertEquals(1,count("SELECT count(*) FROM task_events WHERE task_id=? AND type='DISPATCHED'",t));
        assertEquals(2,count("SELECT count(*) FROM attachments WHERE task_id=?",t));
        assertEquals(1,count("SELECT count(*) FROM idempotency_keys WHERE actor_id=? AND key=? AND hash_version=2",id.get("leader"),k));
    }

    @Test void concurrentReplayCreatesOne() throws Exception {
        String k=key(); var b=body("并发派发","alice"); long before=companyTasks();
        var pool=Executors.newFixedThreadPool(8); var results=new ArrayList<Future<String>>();
        for(int i=0;i<8;i++) results.add(pool.submit(()->requestTask("leader",b,k).get("id").asText()));
        var ids=new HashSet<String>(); for(var f:results) ids.add(f.get(30,TimeUnit.SECONDS)); pool.shutdown();
        assertEquals(1,ids.size()); assertEquals(before,companyTasks());
        approveTaskRevision(ids.iterator().next());
        String taskId=db.one("SELECT target_id FROM review_requests WHERE id=?",ids.iterator().next()).get("target_id").toString();
        assertEquals(before+1,companyTasks());
        assertEquals(1,count("SELECT count(*) FROM task_events WHERE task_id=? AND type='DISPATCHED'",taskId));
    }

    @Test void sameKeyDifferentContentConflicts() throws Exception {
        String k=key(); String t=dispatch("leader",body("原内容","alice"),k).get("id").asText();
        assertEquals("IDEMPOTENCY_CONFLICT",error(409,"leader",body("改过的内容","alice"),k));
        assertEquals("IDEMPOTENCY_CONFLICT",error(409,"leader",body("原内容","amy"),k));
        assertEquals("原内容",call(200,"GET","/tasks/"+t,"alice",null,null).get("title").asText());
    }

    @Test void sameKeyDifferentIssuers() throws Exception {
        String k=key();
        String t1=dispatch("leader",body("组长一的任务","alice"),k).get("id").asText();
        String t2=dispatch("director",body("组长一的任务","alice"),k).get("id").asText();
        assertNotEquals(t1,t2); assertEquals(id.get("director"),call(200,"GET","/tasks/"+t2,"director",null,null).get("issuer_id").asText());
        // 范围外的人用同一键探测，也只按自己的范围处理
        String t3=dispatch("leader2",body("组长一的任务","carl"),k).get("id").asText();
        assertNotEquals(t1,t3); call(404,"GET","/tasks/"+t1,"leader2",null,null);
    }

    @Test void replayAfterStateChangeReturnsCurrent() throws Exception {
        String k=key(); var b=body("状态变化后重放","alice"); String t=dispatch("leader",b,k).get("id").asText();
        event(t,"alice","RECEIVED",1,null);
        var again=dispatch("leader",b,k); assertEquals(t,again.get("id").asText()); assertEquals(2,again.get("version").asInt());
        assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",t).get("phase"));
        event(t,"leader","WITHDRAWN",2,"需求取消");
        assertEquals(3,dispatch("leader",b,k).get("version").asInt());
        assertEquals("WITHDRAWN",db.one("SELECT phase FROM tasks WHERE id=?",t).get("phase"));
        assertEquals(1,count("SELECT count(*) FROM task_events WHERE task_id=? AND type='DISPATCHED'",t));
    }

    // 6.3 非法状态与校验
    @Test void invalidRequestsLeaveNothing() throws Exception {
        long tasks=companyTasks(), keys=count("SELECT count(*) FROM idempotency_keys WHERE company_id=?",company);
        for(var e:Map.of("phase","ACCEPTED","version",3,"completion","100%","status","DONE","issuerId",id.get("reviewer")).entrySet()) {
            var b=body("服务端字段","alice"); b.put(e.getKey(),e.getValue()); assertEquals("SERVER_MANAGED_FIELD",error(400,"leader",b,key()),e.getKey());
        }
        var unknown=body("未知字段","alice"); unknown.put("color","red"); assertEquals("UNKNOWN_FIELD",error(400,"leader",unknown,key()));
        var noTitle=body("x","alice"); noTitle.remove("title"); assertEquals("INVALID_FIELD",error(400,"leader",noTitle,key()));
        var naive=body("无时区","alice"); naive.put("deadline","2026-10-20T18:00"); assertEquals("INVALID_DATE",error(400,"leader",naive,key()));
        var urgency=body("紧急度","alice"); urgency.put("urgency","HIGH"); assertEquals("INVALID_URGENCY",error(400,"leader",urgency,key()));
        assertEquals("IDEMPOTENCY_REQUIRED",error(400,"leader",body("缺键","alice"),null));
        assertEquals("IDEMPOTENCY_REQUIRED",error(400,"leader",body("空键","alice"),"   "));
        assertEquals("IDEMPOTENCY_REQUIRED",error(400,"leader",body("长键","alice"),"k".repeat(129)));
        assertEquals("FORBIDDEN",error(403,"alice",body("员工派发","amy"),key()));
        assertEquals("FORBIDDEN",error(403,"muted",body("撤权派发","alice"),key()));
        assertEquals(tasks,companyTasks()); assertEquals(keys,count("SELECT count(*) FROM idempotency_keys WHERE company_id=?",company));
    }

    @Test void initialStateAndNoCompletionFields() throws Exception {
        var r=dispatch("leader",body("初始状态","alice"),key());
        assertEquals(1,r.get("version").asInt()); assertEquals("DISPATCHED",db.one("SELECT phase FROM tasks WHERE id=?",r.get("id").asText()).get("phase"));
        for(String f:List.of("phase","status","completion","completed","progress")) { assertFalse(r.has(f),f); assertFalse(r.get("fields").has(f),f); }
        assertEquals("NORMAL",r.at("/fields/urgency").asText());
    }

    // 6.4 越权读取
    @Test void readScope() throws Exception {
        String t=dispatch("leader",body("范围任务","alice","amy"),key()).get("id").asText();
        for(String who:List.of("leader2","carl","mia","outsider")) {
            var r=call(404,"GET","/tasks/"+t,who,null,null); assertEquals("NOT_FOUND",r.get("code").asText(),who);
            assertFalse(r.has("title")||r.has("events")||r.has("fields"),who);
        }
        for(String who:List.of("leader","alice","amy","director")) assertEquals(t,call(200,"GET","/tasks/"+t,who,null,null).get("id").asText(),who);
    }

    // 6.5 附件与回滚
    @Test void attachments() throws Exception {
        String own=upload("leader"); var b=body("附件任务","alice"); b.put("attachments",List.of(own));
        String t=dispatch("leader",b,key()).get("id").asText();
        assertEquals(t,db.one("SELECT task_id FROM attachments WHERE id=?",own).get("task_id"));
        var dl=send("GET","/attachments/"+own,"alice",null,null); assertEquals(200,dl.statusCode()); assertEquals("file-of-leader",dl.body());
        long tasks=companyTasks();
        String others=upload("director"); var b2=body("他人附件","alice"); b2.put("attachments",List.of(others));
        assertEquals("FORBIDDEN",error(403,"leader",b2,key()));
        var b3=body("不存在附件","alice"); b3.put("attachments",List.of("no-such-file")); assertEquals("NOT_FOUND",error(404,"leader",b3,key()));
        String foreign=upload("outsider"); var b4=body("他公司附件","alice"); b4.put("attachments",List.of(foreign)); assertEquals("NOT_FOUND",error(404,"leader",b4,key()));
        var b5=body("已绑定附件","alice"); b5.put("attachments",List.of(own)); assertEquals("ATTACHMENT_BOUND",error(409,"leader",b5,key()));
        assertEquals(tasks,companyTasks()); assertEquals(t,db.one("SELECT task_id FROM attachments WHERE id=?",own).get("task_id"));
        assertNull(db.one("SELECT task_id FROM attachments WHERE id=?",others).get("task_id"));
    }

    @Test void failureRollsBackEverything() throws Exception {
        // 附件在参与人、任务行之后绑定：第二个附件失败时，第一个附件、任务、参与人、事件、幂等记录都必须回滚
        String ok=upload("leader"); String bound=upload("leader");
        var pre=body("占用附件","alice"); pre.put("attachments",List.of(bound)); dispatch("leader",pre,key());
        long tasks=companyTasks(), events=count("SELECT count(*) FROM task_events WHERE company_id=?",company), assignees=count("SELECT count(*) FROM task_assignees WHERE company_id=?",company), outbox=count("SELECT count(*) FROM outbox_events WHERE company_id=?",company);
        String k=key(); var b=body("回滚任务","alice","amy"); b.put("attachments",List.of(ok,bound));
        assertEquals("ATTACHMENT_BOUND",error(409,"leader",b,k));
        assertEquals(tasks,companyTasks()); assertEquals(events,count("SELECT count(*) FROM task_events WHERE company_id=?",company));
        assertEquals(assignees,count("SELECT count(*) FROM task_assignees WHERE company_id=?",company)); assertEquals(outbox,count("SELECT count(*) FROM outbox_events WHERE company_id=?",company));
        assertEquals(0,count("SELECT count(*) FROM idempotency_keys WHERE actor_id=? AND key=?",id.get("leader"),k));
        assertNull(db.one("SELECT task_id FROM attachments WHERE id=?",ok).get("task_id"));
    }

    // 6.6 无角色参与人集合
    @Test void participants() throws Exception {
        var r=dispatch("leader",body("去重","alice","amy","alice","amy","leader"),key()); String t=r.get("id").asText();
        assertEquals(List.of(id.get("alice"),id.get("amy"),id.get("leader")).stream().sorted().toList(),
                TaskParticipants.list(db,t).stream().map(row->row.get("id").toString()).sorted().toList());
        assertEquals(List.of(id.get("alice"),id.get("amy"),id.get("leader")).stream().sorted().toList(),
                r.get("participants").findValuesAsText("id").stream().sorted().toList());
        long tasks=companyTasks();
        assertEquals("FORBIDDEN",error(403,"leader",body("其他团队负责人","carl"),key()));
        assertEquals("FORBIDDEN",error(403,"leader",body("其他团队协作人","alice","carl"),key()));
        assertEquals("FORBIDDEN",error(403,"leader",body("其他部门","mia"),key()));
        assertEquals("NOT_FOUND",error(404,"leader",body("其他公司","outsider"),key()));
        assertEquals("NOT_FOUND",error(404,"leader",body("待审核","pending"),key()));
        assertEquals("NOT_FOUND",error(404,"leader",body("停用","alice","disabled"),key()));
        assertEquals(tasks,companyTasks());
    }

    /** 标签由创始人维护；任务仅保存一个活动且可见标签，并返回服务端颜色。 */
    @Test void labelsEnforceFounderScopeSingleLinkAndVersion() throws Exception {
        var label=call(200,"POST","/task-labels","founder",Map.of("name","紧急事项","category","业务","color","#2A7FFF"),null);
        String labelId=label.get("id").asText();
        assertEquals("#2A7FFF",label.get("color").asText());
        assertEquals("FORBIDDEN",call(403,"POST","/task-labels","leader",Map.of("name","越权","category","业务","color","#2A7FFF"),null).get("code").asText());

        var taskBody=body("标签任务","alice"); taskBody.put("labelId",labelId);
        var task=dispatch("leader",taskBody,key());
        assertEquals(labelId,task.get("label").get("id").asText());
        assertEquals("#2A7FFF",task.get("label").get("color").asText());
        assertEquals(1,count("SELECT count(*) FROM task_label_links WHERE task_id=?",task.get("id").asText()));

        var stale=new LinkedHashMap<String,Object>(Map.of("name","紧急事项","category","业务","color","#2A7FFF","status","DISABLED","version",0));
        assertEquals("VERSION_CONFLICT",call(409,"PUT","/task-labels/"+labelId,"founder",stale,null).get("code").asText());
        stale.put("version",1);
        assertEquals("DISABLED",call(200,"PUT","/task-labels/"+labelId,"founder",stale,null).get("status").asText());
        var disabled=body("停用标签","alice"); disabled.put("labelId",labelId);
        assertEquals("INVALID_LABEL",error(400,"leader",disabled,key()));
    }

    /** 评论公开可读但仅任务范围内可写；回复、幂等、空内容和追加约束均由服务端执行。 */
    @Test void taskCommentsValidateScopeRepliesAndAppendOnly() throws Exception {
        String taskId=dispatch("leader",body("评论任务","alice","amy"),key()).get("id").asText();
        String commentKey=key();
        var first=call(200,"POST","/tasks/"+taskId+"/comments","alice",Map.of("text","已完成初稿"),commentKey);
        assertEquals(id.get("alice"),first.get("author_id").asText());
        var reply=call(200,"POST","/tasks/"+taskId+"/comments","leader",Map.of("text","收到，请补充截图","parentId",first.get("id").asText()),key());
        assertEquals(first.get("id").asText(),reply.get("parent_id").asText());
        assertEquals(2,call(200,"GET","/tasks/"+taskId+"/comments","amy",null,null).get("items").size());
        assertEquals("INVALID_COMMENT",call(400,"POST","/tasks/"+taskId+"/comments","alice",Map.of("text","   "),key()).get("code").asText());
        assertEquals("DUPLICATE_COMMENT",call(409,"POST","/tasks/"+taskId+"/comments","alice",Map.of("text","已完成初稿"),commentKey).get("code").asText());
        assertEquals("NOT_FOUND",call(404,"GET","/tasks/"+taskId+"/comments","outsider",null,null).get("code").asText());
        assertThrows(Exception.class,()->jdbc.update("UPDATE task_comments SET body='篡改' WHERE id=?",first.get("id").asText()));
        assertThrows(Exception.class,()->jdbc.update("DELETE FROM task_comments WHERE id=?",reply.get("id").asText()));
    }

    /** 转派和改期在复核通过前不生效；最终生效使用申请时版本，过期申请不得覆盖后来变更。 */
    @Test void approvedReassignmentAndRescheduleRespectReviewAndVersion() throws Exception {
        String taskId=dispatch("leader",body("复核转派改期","alice"),key()).get("id").asText();
        String newDeadline=LocalDate.now(ZoneId.of("Asia/Shanghai")).plusDays(10).atTime(18,0)
                .atZone(ZoneId.of("Asia/Shanghai")).toOffsetDateTime().toString();
        event(taskId,"alice","RECEIVED",1,null);

        var reassignment=call(200,"POST","/tasks/"+taskId+"/reassignments","leader",
                Map.of("ownerId",id.get("amy"),"version",2,"reason","负责人调整"),null);
        assertEquals(id.get("alice"),db.one("SELECT owner_id FROM tasks WHERE id=?",taskId).get("owner_id"));
        assertEquals(2,((Number)db.one("SELECT version FROM tasks WHERE id=?",taskId).get("version")).intValue());
        approveTaskRevision(reassignment.get("id").asText());
        var reassigned=db.one("SELECT owner_id,phase,version FROM tasks WHERE id=?",taskId);
        assertEquals(id.get("amy"),reassigned.get("owner_id"));
        assertEquals("DISPATCHED",reassigned.get("phase"));
        assertEquals(3,((Number)reassigned.get("version")).intValue());
        call(404,"GET","/tasks/"+taskId,"alice",null,null);
        call(200,"GET","/tasks/"+taskId,"amy",null,null);
        assertEquals("REASSIGNED",db.one("SELECT type FROM task_events WHERE task_id=? ORDER BY sequence DESC LIMIT 1",taskId).get("type"));

        var reschedule=call(200,"POST","/tasks/"+taskId+"/reschedules","leader",
                Map.of("deadline",newDeadline,"version",3,"reason","排期调整"),null);
        assertEquals(OffsetDateTime.parse(deadline).toInstant(),((java.sql.Timestamp)db.one("SELECT deadline FROM tasks WHERE id=?",taskId).get("deadline")).toInstant());
        approveTaskRevision(reschedule.get("id").asText());
        var rescheduled=db.one("SELECT phase,version,deadline FROM tasks WHERE id=?",taskId);
        assertEquals("DISPATCHED",rescheduled.get("phase"));
        assertEquals(4,((Number)rescheduled.get("version")).intValue());
        assertEquals(OffsetDateTime.parse(newDeadline).toInstant(),((java.sql.Timestamp)rescheduled.get("deadline")).toInstant());
        assertEquals("RESCHEDULED",db.one("SELECT type FROM task_events WHERE task_id=? ORDER BY sequence DESC LIMIT 1",taskId).get("type"));

        String staleTask=dispatch("leader",body("过期改期申请","alice"),key()).get("id").asText();
        var stale=call(200,"POST","/tasks/"+staleTask+"/reschedules","leader",
                Map.of("deadline",newDeadline,"version",1,"reason","等待复核"),null);
        event(staleTask,"alice","RECEIVED",1,null);
        var conflict=call(409,"POST","/reviews/"+stale.get("id").asText()+"/decision","reviewer",
                Map.of("approve",true,"reason","版本已过期","expectedVersion",1),null);
        assertEquals("VERSION_CONFLICT",conflict.get("code").asText());
        assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",staleTask).get("phase"));
        assertEquals(2,((Number)db.one("SELECT version FROM tasks WHERE id=?",staleTask).get("version")).intValue());
    }

    /** 删除必须走独立审核：驳回不改任务，批准只归档；等待审核的旧版本不得覆盖新状态。 */
    @Test void deletionRequiresIndependentReviewAndNeverPhysicallyRemovesTask() throws Exception {
        String rejectedTask=dispatch("leader",body("删除驳回任务","alice"),key()).get("id").asText();
        var rejected=call(200,"POST","/tasks/"+rejectedTask+"/deletions","leader",
                Map.of("version",1,"reason","不再需要"),null);
        assertEquals("TASK_DELETE",rejected.get("kind").asText());
        assertEquals("DISPATCHED",db.one("SELECT phase FROM tasks WHERE id=?",rejectedTask).get("phase"));
        // 申请人不在审核链中，不能给自己的删除申请作决定。
        assertEquals("SELF_REVIEW",call(403,"POST","/reviews/"+rejected.get("id").asText()+"/decision","leader",
                Map.of("approve",true,"reason","自审","expectedVersion",1),null).get("code").asText());
        var firstPending=db.rows("SELECT reviewer_id FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",rejected.get("id").asText()).getFirst();
        String rejector=id.entrySet().stream().filter(e->e.getValue().equals(firstPending.get("reviewer_id"))).map(Map.Entry::getKey).findFirst().orElseThrow();
        call(200,"POST","/reviews/"+rejected.get("id").asText()+"/decision",rejector,
                Map.of("approve",false,"reason","仍需保留","expectedVersion",1),null);
        assertEquals("DISPATCHED",db.one("SELECT phase FROM tasks WHERE id=?",rejectedTask).get("phase"));
        assertEquals(1,((Number)db.one("SELECT version FROM tasks WHERE id=?",rejectedTask).get("version")).intValue());

        String approvedTask=dispatch("leader",body("删除归档任务","alice"),key()).get("id").asText();
        var approved=call(200,"POST","/tasks/"+approvedTask+"/deletions","leader",
                Map.of("version",1,"reason","需求取消"),null);
        approveTaskRevision(approved.get("id").asText());
        assertEquals(1,count("SELECT count(*) FROM tasks WHERE id=?",approvedTask));
        assertEquals("ARCHIVED",db.one("SELECT phase FROM tasks WHERE id=?",approvedTask).get("phase"));
        assertEquals(2,((Number)db.one("SELECT version FROM tasks WHERE id=?",approvedTask).get("version")).intValue());
        assertEquals("TASK_DELETED_BY_REVIEW",db.one("SELECT type FROM audit_records WHERE object_id=? ORDER BY created_at DESC LIMIT 1",approvedTask).get("type"));

        String staleTask=dispatch("leader",body("删除版本冲突任务","alice"),key()).get("id").asText();
        var stale=call(200,"POST","/tasks/"+staleTask+"/deletions","leader",
                Map.of("version",1,"reason","等待审核"),null);
        event(staleTask,"alice","RECEIVED",1,null);
        var pending=db.rows("SELECT reviewer_id FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position",stale.get("id").asText());
        for(int i=0;i<pending.size()-1;i++) {
            Object reviewer=pending.get(i).get("reviewer_id");
            String who=id.entrySet().stream().filter(e->e.getValue().equals(reviewer)).map(Map.Entry::getKey).findFirst().orElseThrow();
            call(200,"POST","/reviews/"+stale.get("id").asText()+"/decision",who,Map.of("approve",true,"reason","同意"),null);
        }
        String finalReviewer=id.entrySet().stream().filter(e->e.getValue().equals(pending.getLast().get("reviewer_id"))).map(Map.Entry::getKey).findFirst().orElseThrow();
        assertEquals("VERSION_CONFLICT",call(409,"POST","/reviews/"+stale.get("id").asText()+"/decision",finalReviewer,
                Map.of("approve",true,"reason","版本已变化","expectedVersion",1),null).get("code").asText());
        assertEquals("RECEIVED",db.one("SELECT phase FROM tasks WHERE id=?",staleTask).get("phase"));
        assertEquals(2,((Number)db.one("SELECT version FROM tasks WHERE id=?",staleTask).get("version")).intValue());
    }

    /** 日报草稿、提交、修订、下属可见性、已读评语和任务关联在真实 HTTP/数据库链路中保持一致。 */
    @Test void dailyLogWorkflowKeepsDraftPrivateAndHistoryConsistent() throws Exception {
        String date=LocalDate.now(ZoneId.of("Asia/Shanghai")).toString();
        String taskId=dispatch("leader",body("日报关联任务","alice"),key()).get("id").asText();
        var firstBody=new LinkedHashMap<String,Object>();
        firstBody.put("work","完成初稿"); firstBody.put("tomorrow","继续联调"); firstBody.put("taskIds",List.of(taskId,taskId));
        var draft=call(200,"PUT","/logs/draft","alice",Map.of("businessDate",date,"version",0,"body",firstBody),null);
        String logId=draft.get("id").asText();
        assertFalse(draft.get("submitted").asBoolean()); assertEquals(1,draft.get("version").asInt());
        assertEquals(1,count("SELECT count(*) FROM daily_logs WHERE owner_id=? AND business_date=?::date",id.get("alice"),date));
        assertEquals(1,count("SELECT count(*) FROM log_tasks WHERE company_id=? AND log_id=?",company,logId));
        call(404,"GET","/logs/"+logId,"leader",null,null);
        assertTrue(call(200,"GET","/logs/subordinates?ownerId="+id.get("alice")+"&date="+date,"leader",null,null).get("items").isEmpty());

        var secondBody=new LinkedHashMap<String,Object>(firstBody); secondBody.put("work","覆盖后的草稿");
        var updated=call(200,"PUT","/logs/draft","alice",Map.of("businessDate",date,"version",1,"body",secondBody),null);
        assertEquals(logId,updated.get("id").asText()); assertEquals(2,updated.get("version").asInt());
        var stale=call(409,"PUT","/logs/draft","alice",Map.of("businessDate",date,"version",1,"body",firstBody),null);
        assertEquals("VERSION_CONFLICT",stale.get("code").asText());

        var submitted=call(200,"POST","/logs/"+logId+"/submit","alice",Map.of("version",2),null);
        assertTrue(submitted.get("submitted").asBoolean()); assertEquals(3,submitted.get("version").asInt());
        assertEquals(1,count("SELECT count(*) FROM log_versions WHERE log_id=?",logId));
        call(200,"GET","/logs/"+logId,"leader",null,null);
        assertTrue(call(200,"GET","/logs/subordinates?ownerId="+id.get("alice")+"&date="+date,"leader",null,null).get("items").size()>0);
        call(200,"POST","/logs/"+logId+"/comments","leader",Map.of("text","请继续保持"),null);
        assertEquals(1,call(200,"GET","/logs/"+logId+"/comments","leader",null,null).size());

        Object first=db.one("SELECT submitted_at FROM daily_logs WHERE id=?",logId).get("submitted_at");
        var revised=call(200,"PUT","/logs/"+logId+"/content","alice",Map.of("version",3,"work","直接更新的正文"),null);
        assertEquals(4,revised.get("version").asInt()); assertEquals("直接更新的正文",revised.get("body").get("work").asText());
        assertEquals(first,db.one("SELECT submitted_at FROM daily_logs WHERE id=?",logId).get("submitted_at"));
        var versions=call(200,"GET","/logs/"+logId+"/versions","leader",null,null);
        assertEquals(List.of(3,4),versions.findValuesAsText("version").stream().map(Integer::parseInt).toList());
        call(200,"PUT","/logs/"+logId+"/content","alice",Map.of("version",4,"work","先保存的正文"),null);
        assertEquals("VERSION_CONFLICT",call(409,"PUT","/logs/"+logId+"/content","alice",Map.of("version",4,"work","过期覆盖"),null).get("code").asText());
        assertEquals("先保存的正文",call(200,"GET","/logs/"+logId,"alice",null,null).get("body").get("work").asText());
    }

    /** 直接写入带显式时间区间的任务夹具；查询链路仍全部经由 HTTP。 */
    String scheduledTask(String title,String startAt,String deadline,String phase) {
        String tid="sched-"+UUID.randomUUID();
        jdbc.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase) VALUES (?,?,?,?,?,?::timestamptz,?::timestamptz,'{}'::jsonb,?)",
            tid,company,id.get("alice"),id.get("leader"),title,startAt,deadline,phase);
        jdbc.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?)",tid,id.get("alice"),company);
        return tid;
    }
    void dispatchedEvent(String taskId,String at) {
        jdbc.update("INSERT INTO task_events(company_id,task_id,actor_id,type,body,created_at) VALUES (?,?,?,'DISPATCHED','{}'::jsonb,?::timestamptz)",
            company,taskId,id.get("leader"),at);
    }
    Set<String> rangeIds(String search,String from,String to) throws Exception {
        var page=list(200,"search="+search+"&limit=100&from="+from+"&to="+to,"leader");
        var ids=new LinkedHashSet<String>();
        page.get("items").forEach(item->ids.add(item.get("id").asText()));
        return ids;
    }
    static java.time.Instant at(String text) { return java.time.OffsetDateTime.parse(text).toInstant(); }

    /** 任务区间 [start_at, deadline] 与查询区间 [from, to) 左闭右开相交；空 start_at 与反向脏数据按契约处理。 */
    @Test void taskRangeQueryIntersectsHalfOpenIntervalAndRejectsConflicts() throws Exception {
        String prefix="range-"+UUID.randomUUID();
        String spanning=scheduledTask(prefix+"-spanning","2026-10-01T00:00:00Z","2026-10-31T00:00:00Z","RECEIVED");
        scheduledTask(prefix+"-next","2026-11-01T00:00:00Z","2026-11-15T00:00:00Z","DISPATCHED");
        String withoutStart=scheduledTask(prefix+"-nostart",null,"2026-10-15T00:00:00Z","DISPATCHED");
        scheduledTask(prefix+"-reversed","2026-12-01T00:00:00Z","2026-11-01T00:00:00Z","DISPATCHED");

        // deadline 恰好等于 from 命中；start_at 恰好等于 to 不命中；空 start_at 按 deadline 时间点判定。
        assertEquals(Set.of(spanning),rangeIds(prefix,"2026-10-31T00:00:00Z","2026-11-01T00:00:00Z"));
        // 跨月覆盖：跨月任务与无 start_at 任务命中，下月才开始的任务不命中。
        assertEquals(Set.of(spanning,withoutStart),rangeIds(prefix,"2026-10-01T00:00:00Z","2026-11-01T00:00:00Z"));
        // 旧 date/period 调用保持兼容并返回同一集合。
        var legacy=list(200,"search="+prefix+"&date=2026-10-31&period=day&limit=100","leader");
        assertEquals(1,legacy.get("total").asInt()); assertEquals(spanning,legacy.get("items").get(0).get("id").asText());
        // 反向区间脏数据在任何覆盖范围内都不得命中。
        var dirty=list(200,"search="+prefix+"-reversed&limit=10&from=2026-10-01T00:00:00Z&to=2026-12-10T00:00:00Z","leader");
        assertEquals(0,dirty.get("total").asInt()); assertEquals(0,dirty.get("items").size());

        assertEquals("INVALID_RANGE",list(400,"search="+prefix+"&from=2026-10-01T00:00:00Z","leader").get("code").asText());
        assertEquals("INVALID_RANGE",list(400,"search="+prefix+"&to=2026-11-01T00:00:00Z","leader").get("code").asText());
        assertEquals("INVALID_RANGE",list(400,"search="+prefix+"&from=2026-10-01T00:00:00Z&to=2026-11-01T00:00:00Z&date=2026-10-01","leader").get("code").asText());
        assertEquals("INVALID_RANGE",list(400,"search="+prefix+"&from=2026-11-01T00:00:00Z&to=2026-10-01T00:00:00Z","leader").get("code").asText());
        assertEquals("INVALID_RANGE",list(400,"search="+prefix+"&from=2026-10-01T00:00:00&to=2026-11-01T00:00:00","leader").get("code").asText());
        assertEquals("INVALID_PARTICIPANT_FILTER",list(400,"participantId="+id.get("alice")+"&ownerId="+id.get("amy"),"leader").get("code").asText());
        assertEquals(1,list(200,"search="+prefix+"-spanning&participantId="+id.get("alice")+"&ownerId="+id.get("alice")+"&limit=10","leader").get("total").asInt());
        // 区间查询不能成为越权探测通道。
        assertEquals("FORBIDDEN",list(403,"search="+prefix+"&from=2026-10-01T00:00:00Z&to=2026-11-01T00:00:00Z&participantId="+id.get("carl"),"leader").get("code").asText());
        assertEquals("NOT_FOUND",list(404,"from=2026-10-01T00:00:00Z&to=2026-11-01T00:00:00Z&participantId="+id.get("outsider"),"leader").get("code").asText());
    }

    /** 接收卡片使用最早真实 DISPATCHED 时间、缺失置后、id 稳定排序，并保留撤回/验收/归档历史。 */
    @Test void receivedCardOrdersByEarliestDispatchAndKeepsTerminalPhases() throws Exception {
        String prefix="card-"+UUID.randomUUID();
        String first=scheduledTask(prefix+"-first",null,"2026-10-20T00:00:00Z","ACCEPTED");
        String second=scheduledTask(prefix+"-second",null,"2026-10-21T00:00:00Z","ARCHIVED");
        String withdrawn=scheduledTask(prefix+"-withdrawn",null,"2026-10-22T00:00:00Z","WITHDRAWN");
        String undated=scheduledTask(prefix+"-undated",null,"2026-10-23T00:00:00Z","DISPATCHED");
        // 同一任务多次派发取最早时间；同时间的三条按 id 升序；无派发事件排最后。
        dispatchedEvent(first,"2026-10-15T03:00:00Z"); dispatchedEvent(first,"2026-10-12T01:00:00Z");
        dispatchedEvent(second,"2026-10-12T01:00:00Z");
        dispatchedEvent(withdrawn,"2026-10-12T01:00:00Z");

        var page=call(200,"GET","/tasks/received-card?search="+prefix+"&limit=100","leader",null,null);
        assertEquals(4,page.get("total").asInt());
        var expected=new ArrayList<>(List.of(first,second,withdrawn)); expected.sort(Comparator.naturalOrder()); expected.add(undated);
        var actual=new ArrayList<String>(); page.get("items").forEach(item->actual.add(item.get("id").asText()));
        assertEquals(expected,actual);
        Map<String,JsonNode> byId=new HashMap<>(); page.get("items").forEach(item->byId.put(item.get("id").asText(),item));
        var names=new HashSet<String>(); byId.get(first).fieldNames().forEachRemaining(names::add);
        assertEquals(Set.of("id","title","start_at","deadline","version","phase","created_at","dispatchAt","participants","label"),names);
        assertEquals(at("2026-10-12T01:00:00Z"),at(byId.get(first).get("dispatchAt").asText()));
        assertEquals("ACCEPTED",byId.get(first).get("phase").asText());
        assertEquals("WITHDRAWN",byId.get(withdrawn).get("phase").asText());
        assertTrue(byId.get(undated).get("dispatchAt").isNull());

        var p1=call(200,"GET","/tasks/received-card?search="+prefix+"&limit=2&cursor=0","leader",null,null);
        var p2=call(200,"GET","/tasks/received-card?search="+prefix+"&limit=2&cursor="+p1.get("nextCursor").asText(),"leader",null,null);
        assertEquals("2",p1.get("nextCursor").asText());
        var paged=new ArrayList<String>(); p1.get("items").forEach(item->paged.add(item.get("id").asText())); p2.get("items").forEach(item->paged.add(item.get("id").asText()));
        assertEquals(expected,paged);

        assertTrue(call(200,"GET","/tasks/received-card?search="+prefix+"&limit=100","alice",null,null).get("total").asInt()>=1);
        assertEquals(0,call(200,"GET","/tasks/received-card?search="+prefix+"&limit=100","outsider",null,null).get("total").asInt());
        assertEquals("INVALID_SEARCH",call(400,"GET","/tasks/received-card?search="+"x".repeat(201),"leader",null,null).get("code").asText());
        assertEquals("INVALID_PAGE",call(400,"GET","/tasks/received-card?limit=101","leader",null,null).get("code").asText());
    }

    private void approveTaskRevision(String reviewId) throws Exception {
        while(true) {
            var pending=db.rows("SELECT reviewer_id FROM review_steps WHERE request_id=? AND state='PENDING' ORDER BY position LIMIT 1",reviewId);
            if(pending.isEmpty()) return;
            String reviewer=pending.getFirst().get("reviewer_id").toString();
            String who=id.entrySet().stream().filter(entry->entry.getValue().equals(reviewer)).map(Map.Entry::getKey).findFirst().orElseThrow();
            int expected=((Number)db.one("SELECT expected_version FROM review_requests WHERE id=?",reviewId).get("expected_version")).intValue();
            call(200,"POST","/reviews/"+reviewId+"/decision",who,Map.of("approve",true,"reason","同意","expectedVersion",expected),null);
        }
    }
}
