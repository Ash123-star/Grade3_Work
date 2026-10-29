package cn.workpanel.module.log;

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

import static org.junit.jupiter.api.Assertions.*;

/**
 * 下属日志列表、成员月状态与详情授权的真实 PostgreSQL/Redis + HTTP 契约测试。
 * 组织夹具直接写库（每次运行使用独立公司 ID），业务读写全部经由 HTTP。
 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT, properties={
    "app.admin-account=integration-admin", "app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001", "app.deepseek-key=local-mock-only", "app.jobs-enabled=false"
})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class LogSubordinateContractIntegrationTest {
    static final ZoneId SHANGHAI=ZoneId.of("Asia/Shanghai");
    static final String EMPLOYMENT="2024-06-01";
    static final ObjectMapper JSON=new ObjectMapper();
    @LocalServerPort int port;
    @Autowired Db db;
    @Autowired JdbcTemplate jdbc;
    @Autowired StringRedisTemplate redis;
    final HttpClient http=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    final String run=UUID.randomUUID().toString().substring(0,8);
    final String company="log-"+run, other="log-other-"+run, department=department("log-"+run,"d1"), otherDepartment=department("log-"+run,"d2");
    final Map<String,String> token=new HashMap<>(), id=new HashMap<>();

    static String department(String company,String name) { return company+"-"+name; }

    @BeforeAll void fixtures() {
        for(String c:List.of(company,other)) {
            jdbc.update("INSERT INTO companies(id,name) VALUES (?,?)",c,"日志公司"+c);
            jdbc.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",department(c,"d1"),c,"研发部");
            jdbc.update("INSERT INTO departments(id,company_id,name) VALUES (?,?,?)",department(c,"d2"),c,"市场部");
            jdbc.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?)",c+"-t1",c,department(c,"d1"),"研发一组");
            jdbc.update("INSERT INTO teams(id,company_id,department_id,name) VALUES (?,?,?,?)",c+"-t2",c,department(c,"d2"),"市场一组");
        }
        user("admin",company,"ADMIN","d1",null,"ACTIVE");
        user("director",company,"DIRECTOR","d1",null,"ACTIVE");
        user("leaderTeam",company,"LEADER","d1","t1","ACTIVE");
        user("leaderOther",company,"LEADER","d2","t2","ACTIVE");
        user("employee",company,"EMPLOYEE","d1","t1","ACTIVE");
        user("employeeNoDate",company,"EMPLOYEE","d1","t1","ACTIVE");
        user("employeeOther",company,"EMPLOYEE","d1","t1","ACTIVE");
        user("departed",company,"EMPLOYEE","d1","t1","DISABLED");
        user("outsider",other,"ADMIN","d1",null,"ACTIVE");
        jdbc.update("UPDATE users SET employment_start_date=?::date WHERE id=?",EMPLOYMENT,id.get("employee"));
    }

    /** 每个场景独立夹具：清理日志并重建直属关系，避免用例互相污染。 */
    @BeforeEach void reset() {
        redis.delete(redis.keys("workpanel:api:*"));
        jdbc.update("DELETE FROM log_versions WHERE company_id=?",company);
        jdbc.update("DELETE FROM daily_logs WHERE company_id=?",company);
        jdbc.update("DELETE FROM reporting_relations WHERE company_id=?",company);
        jdbc.update("UPDATE users SET status='ACTIVE',employment_start_date=?::date WHERE id=?",EMPLOYMENT,id.get("employee"));
        jdbc.update("UPDATE users SET employment_start_date=NULL WHERE id=?",id.get("employeeNoDate"));
        jdbc.update("INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES (?,?,?)",id.get("employee"),id.get("leaderOther"),company);
    }

    void user(String who,String c,String role,String dept,String team,String status) {
        String uid=c+"-"+who; id.put(who,uid);
        jdbc.update("INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            uid,c,uid,"x","p-"+uid,who,dept==null?null:department(c,dept),team==null?null:c+"-"+team,role,status,true);
        String t=UUID.randomUUID().toString(); token.put(who,t);
        jdbc.update("INSERT INTO sessions VALUES (?,?,now()+interval '1 hour')",Db.hash(t),uid);
    }

    HttpResponse<String> send(String method,String path,String who) throws Exception {
        var builder=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+"/api"+path)).timeout(Duration.ofSeconds(15));
        if(who!=null) builder.header("Authorization","Bearer "+token.get(who));
        return http.send(builder.method(method,HttpRequest.BodyPublishers.noBody()).build(),HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    }
    JsonNode call(int status,String method,String path,String who) throws Exception {
        var response=send(method,path,who); assertEquals(status,response.statusCode(),method+" "+path+" "+response.body());
        return JSON.readTree(response.body());
    }
    String log(String owner,LocalDate date,boolean submitted) {
        String logId=Db.id();
        jdbc.update("INSERT INTO daily_logs(id,company_id,owner_id,business_date,body,submitted,submitted_at) VALUES (?,?,?,?::date,?::jsonb,?,?)",
            logId,company,id.get(owner),date.toString(),"{\"work\":\"subordinate contract work "+date+"\"}",submitted,submitted?java.sql.Timestamp.from(date.atTime(9,0).atZone(SHANGHAI).toInstant()):null);
        return logId;
    }
    /** URL 编码的上海零点时刻；query 中的 + 必须转为 %2B。 */
    static String instant(LocalDate date) { return date.atStartOfDay(SHANGHAI).toOffsetDateTime().toString().replace("+","%2B"); }
    static LocalDate today() { return LocalDate.now(SHANGHAI); }

    @Test void calendarReturnsEveryNaturalDayAndNeverGuessesBeforeEmployment() throws Exception {
        var july=call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2025-07","director");
        assertEquals(id.get("employee"),july.get("ownerId").asText());
        assertEquals("2025-07",july.get("month").asText());
        assertEquals(EMPLOYMENT,july.get("employmentStartDate").asText());
        assertEquals(31,july.get("days").size());
        for(int day=1;day<=31;day++) assertEquals("MISSING",july.get("days").get(String.valueOf(day)).asText(),"day "+day);

        assertEquals(30,call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2025-06","director").get("days").size());
        var leap=call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2024-02","director");
        assertEquals(29,leap.get("days").size());
        for(int day=1;day<=29;day++) assertEquals("UNKNOWN",leap.get("days").get(String.valueOf(day)).asText(),"day "+day);

        call(400,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2025-13","director");
        call(400,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2025-7","director");
        call(400,"GET","/logs/subordinates/calendar?month=2025-07","director");
    }

    @Test void calendarMarksSubmittedMissingAndFutureInCurrentMonth() throws Exception {
        LocalDate today=today(); YearMonth month=YearMonth.from(today);
        jdbc.update("UPDATE users SET employment_start_date=?::date WHERE id=?",month.atDay(1).toString(),id.get("employee"));
        log("employee",month.atDay(1),true);
        log("employee",today,true);

        var calendar=call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month="+month,"director");
        assertEquals(month.lengthOfMonth(),calendar.get("days").size());
        assertEquals("SUBMITTED",calendar.get("days").get("1").asText());
        assertEquals("SUBMITTED",calendar.get("days").get(String.valueOf(today.getDayOfMonth())).asText());
        if(today.getDayOfMonth()>2) assertEquals("MISSING",calendar.get("days").get("2").asText());
        if(today.getDayOfMonth()<month.lengthOfMonth()) assertEquals("FUTURE",calendar.get("days").get(String.valueOf(today.getDayOfMonth()+1)).asText());
    }

    @Test void calendarWithoutEmploymentStartDateReturnsUnknownInsteadOfMissing() throws Exception {
        log("employeeNoDate",LocalDate.parse("2025-07-15"),true);
        var calendar=call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employeeNoDate")+"&month=2025-07","director");
        assertTrue(calendar.get("employmentStartDate").isNull());
        assertEquals("SUBMITTED",calendar.get("days").get("15").asText());
        assertEquals("UNKNOWN",calendar.get("days").get("14").asText());
        assertEquals("UNKNOWN",calendar.get("days").get("16").asText());
        var future=call(200,"GET","/logs/subordinates/calendar?ownerId="+id.get("employeeNoDate")+"&month="+YearMonth.from(today()).plusMonths(2),"director");
        assertEquals("FUTURE",future.get("days").get("1").asText());
    }

    @Test void calendarAuthorizationIsRealtimeAndRejectsOutsiders() throws Exception {
        String path="/logs/subordinates/calendar?ownerId="+id.get("employee")+"&month=2025-07";
        call(403,"GET",path,"employee");
        call(403,"GET",path,"employeeOther");
        call(401,"GET",path,"departed");
        call(404,"GET",path,"outsider");
        call(200,"GET",path,"leaderOther");
        call(200,"GET",path,"leaderTeam");
        call(200,"GET",path,"admin");

        jdbc.update("DELETE FROM reporting_relations WHERE company_id=?",company);
        call(403,"GET",path,"leaderOther");
        call(200,"GET",path,"leaderTeam");

        jdbc.update("UPDATE users SET status='DISABLED' WHERE id=?",id.get("employee"));
        call(403,"GET",path,"director");
    }

    @Test void subordinateListUsesHalfOpenShanghaiRangeAndCombinedFilters() throws Exception {
        LocalDate start=LocalDate.parse("2025-08-01");
        String first=log("employee",start,true),second=log("employee",start.plusDays(1),true);
        log("employee",start.plusDays(2),true);
        log("employee",start.plusDays(3),false);

        var range=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&from="+instant(start)+"&to="+instant(start.plusDays(2)),"leaderOther");
        assertEquals(2,range.get("total").asInt());
        assertEquals(second,range.get("items").get(0).get("id").asText());
        assertEquals(first,range.get("items").get(1).get("id").asText());
        assertFalse(range.get("groups").isEmpty());
        assertTrue(range.get("items").get(0).get("submitted").asBoolean());

        var rightOpen=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&from="+instant(start)+"&to="+instant(start.plusDays(1)),"leaderOther");
        assertEquals(1,rightOpen.get("total").asInt()); assertEquals(first,rightOpen.get("items").get(0).get("id").asText());

        var filtered=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&search="+start.plusDays(1)+"&departmentId="+department+"&from="+instant(start)+"&to="+instant(start.plusDays(3)),"leaderOther");
        assertEquals(1,filtered.get("total").asInt()); assertEquals(second,filtered.get("items").get(0).get("id").asText());

        assertEquals(0,call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&departmentId="+otherDepartment,"leaderOther").get("total").asInt());
        assertEquals(0,call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&search=absent","leaderOther").get("total").asInt());
    }

    @Test void subordinateListRejectsConflictingOrMalformedRanges() throws Exception {
        String owner="?ownerId="+id.get("employee");
        String from=instant(LocalDate.parse("2025-08-01")),to=instant(LocalDate.parse("2025-08-03"));
        call(400,"GET","/logs/subordinates"+owner+"&from="+from,"leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&to="+to,"leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+to+"&to="+from,"leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to="+from,"leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to="+to+"&date=2025-08-01","leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to="+to+"&period=month","leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to=2025-08-03T09:30:00%2B08:00","leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from=2025-08-01&to=2025-08-03","leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to="+to+"&search="+"a".repeat(101),"leaderOther");
        call(400,"GET","/logs/subordinates"+owner+"&from="+from+"&to="+to+"&period=week&date=2025-08-01","leaderOther");
    }

    @Test void subordinateListDeniesOutOfScopeAndDrafts() throws Exception {
        String submitted=log("employee",LocalDate.parse("2025-08-05"),true);
        String draft=log("employee",LocalDate.parse("2025-08-06"),false);
        var page=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee"),"leaderOther");
        assertEquals(1,page.get("total").asInt()); assertEquals(submitted,page.get("items").get(0).get("id").asText());

        call(403,"GET","/logs/subordinates","employee");
        call(403,"GET","/logs/subordinates?ownerId="+id.get("employee"),"employeeOther");
        call(404,"GET","/logs/subordinates?ownerId="+id.get("employee"),"outsider");
        call(404,"GET","/logs/"+submitted,"employeeOther");
        call(404,"GET","/logs/"+draft,"leaderOther");
        call(404,"GET","/logs/"+draft,"admin");
        call(200,"GET","/logs/"+draft,"employee");
        call(200,"GET","/logs/"+submitted,"leaderOther");
        call(200,"GET","/logs/"+submitted,"director");
        call(200,"GET","/logs/"+submitted,"admin");
        call(404,"GET","/logs/"+submitted,"outsider");

        jdbc.update("DELETE FROM reporting_relations WHERE company_id=?",company);
        call(403,"GET","/logs/subordinates?ownerId="+id.get("employee"),"leaderOther");
        call(404,"GET","/logs/"+submitted,"leaderOther");
        call(200,"GET","/logs/"+submitted,"leaderTeam");
    }

    @Test void subordinateListKeepsPagingStableAndExcludesSelf() throws Exception {
        LocalDate start=LocalDate.parse("2025-09-01");
        List<String> created=new ArrayList<>();
        for(int day=0;day<4;day++) created.add(log("employee",start.plusDays(day),true));
        log("leaderOther",start,true);

        var firstPage=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&limit=2","leaderOther");
        assertEquals(4,firstPage.get("total").asInt()); assertEquals(2,firstPage.get("items").size());
        var nextPage=call(200,"GET","/logs/subordinates?ownerId="+id.get("employee")+"&limit=2&cursor="+firstPage.get("nextCursor").asText(),"leaderOther");
        assertEquals(2,nextPage.get("items").size());
        var seen=new HashSet<String>();
        for(var page:List.of(firstPage,nextPage)) for(var item:page.get("items")) assertTrue(seen.add(item.get("id").asText()),"重复记录");
        assertEquals(new HashSet<>(created),seen);

        var all=call(200,"GET","/logs/subordinates","leaderOther");
        assertEquals(4,all.get("total").asInt());
        for(var item:all.get("items")) assertNotEquals(id.get("leaderOther"),item.get("owner_id").asText());
        assertEquals(4,call(200,"GET","/logs/subordinates","leaderTeam").get("total").asInt());
    }
}
