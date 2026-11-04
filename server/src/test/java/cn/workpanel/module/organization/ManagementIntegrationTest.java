package cn.workpanel.module.organization;

import cn.workpanel.Db;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={"app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026","app.admin-phone=13900000001"})
public class ManagementIntegrationTest extends MemberBHttpSupport {
    private final String root="/admin/workspace/management";
    @Test void allAccountsAndDirectAccessAreCompanyScoped()throws Exception{
        db.update("UPDATE users SET status='DISABLED' WHERE id=?",outside);
        var result=call(200,"GET",root+"/accounts?limit=100",admin,null);
        assertEquals(8,result.get("total").asInt());assertFalse(result.toString().contains("password_hash"));assertFalse(result.toString().contains(foreign));
        assertEquals(1,call(200,"GET",root+"/accounts?status=DISABLED",admin,null).get("total").asInt());
        call(403,"GET",root+"/accounts",employee,null);call(403,"GET","/management/accounts",founder,null);
        call(404,"GET",root+"/accounts/"+foreign,admin,null);call(400,"GET",root+"/accounts?limit=0",admin,null);
        call(400,"GET",root+"/accounts?search="+"x".repeat(101),admin,null);
    }
    @Test void accountCandidateRequiresIndependentReviewAndUpdatesScope()throws Exception{
        var request=call(200,"POST",root+"/accounts/"+employee+"/revisions",admin,Map.of("name","管理页面调整","version",1,"reason","修正姓名"));
        String id=request.get("id").asText();assertEquals(employee,db.one("SELECT name FROM users WHERE id=?",employee).get("name"));
        call(403,"POST",root+"/reviews/"+id+"/decision",admin,Map.of("approve",true,"reason","自审"));
        approve(id,admin);assertEquals("管理页面调整",db.one("SELECT name FROM users WHERE id=?",employee).get("name"));
        call(409,"POST",root+"/accounts/"+employee+"/revisions",admin,Map.of("name","旧版本","version",1,"reason","冲突"));
        call(400,"POST",root+"/accounts/"+employee+"/revisions",admin,Map.of("version",2,"reason","修改复核权限","companyReviewer",true));
    }
    @Test void itemReviewArchiveAndPublicReadShareOneSource()throws Exception{
        var body=new LinkedHashMap<String,Object>(Map.of("title","公司管理测试事项","text","真实内容","pinned",true,"archived",false,"position",1,"version",0,"reason","发布事项"));
        var request=call(200,"POST",root+"/items/revisions",admin,body);String item=request.get("target_id").asText();
        assertEquals(0,call(200,"GET",root+"/items",admin,null).get("total").asInt());approve(request.get("id").asText(),admin);
        assertEquals("公司管理测试事项",call(200,"GET","/dashboard/company",employee,null).get("items").get(0).get("title").asText());
        var detail=call(200,"GET",root+"/items/"+item,admin,null);assertEquals("真实内容",detail.get("text").asText());
        body.put("id",item);body.put("version",detail.get("version").asInt());body.put("archived",true);
        var archive=call(200,"POST",root+"/items/revisions",admin,body);approve(archive.get("id").asText(),admin);
        assertEquals(0,call(200,"GET","/dashboard/company",employee,null).get("total").asInt());assertEquals(1,call(200,"GET",root+"/items?archived=true",admin,null).get("total").asInt());
        call(403,"GET",root+"/items",employee,null);call(404,"GET",root+"/items/"+Db.id(),admin,null);
    }
    @Test void capacityConflictRollsBackFinalReview()throws Exception{
        for(int n=0;n<10;n++)db.update("INSERT INTO dashboard_items(id,company_id,owner_id,kind,title,body,pinned) VALUES (?,?,?,'COMPANY','置顶','{}'::jsonb,true)",Db.id(),company,admin);
        var request=call(200,"POST",root+"/items/revisions",admin,Map.of("title","第十一项","version",0,"reason","容量测试","pinned",true));String id=request.get("id").asText();
        var detail=call(200,"GET",root+"/reviews/"+id,admin,null);
        for(var step:detail.get("steps")){boolean last=step.get("position").asInt()==detail.get("steps").size();call(last?400:200,"POST","/reviews/"+id+"/decision",step.get("reviewer_id").asText(),Map.of("approve",true,"reason","复核"));}
        assertEquals("PENDING",db.one("SELECT status FROM review_requests WHERE id=?",id).get("status"));
        assertEquals(10,db.count("SELECT count(*) FROM dashboard_items WHERE company_id=? AND pinned AND NOT archived",company));
    }
}
