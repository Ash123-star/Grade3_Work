package cn.workpanel.module.organization;

import cn.workpanel.*;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import cn.workpanel.module.log.application.LogWorkflowService;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

/** 最新日志HTTP/数据库契约；停用路由只做负向验证，不用于业务准备或正常流程。 */
@SpringBootTest(webEnvironment=SpringBootTest.WebEnvironment.RANDOM_PORT,properties={
    "app.admin-account=integration-admin","app.admin-password=Initial-test-password-2026",
    "app.admin-phone=13900000001","app.jobs-enabled=false","app.memory-extract-enabled=false"
})
class CurrentLogContractIntegrationTest extends MemberBHttpSupport {
    @Autowired LogWorkflowService logs;
    String draft(LocalDate date) throws Exception {
        return call(200,"PUT","/logs/draft",employee,Map.of("businessDate",date.toString(),"version",0,
                "body",Map.of("work","原始正文","tomorrow","保留其他历史字段"))).get("id").asText();
    }
    LocalDate today(){return LocalDate.now(ZoneId.of("Asia/Shanghai"));}
    Map<String,Object> row(String id){return db.one("SELECT * FROM daily_logs WHERE id=?",id);}
    String task(String participant,String phase) {
        String id=Db.id();
        db.update("INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,deadline,body,phase) VALUES (?,?,?,?,?,now()+interval '1 day','{}',?)",id,company,participant,admin,"日志今日任务",phase);
        db.update("INSERT INTO task_participants(task_id,user_id,company_id) VALUES (?,?,?)",id,participant,company);
        return id;
    }
    @Test void selectedTasksSurviveDraftSubmissionCompletionAndHistory() throws Exception {
        String first=task(employee,"RECEIVED"),second=task(employee,"RECEIVED");
        String id=call(200,"PUT","/logs/draft",employee,Map.of("businessDate",today().toString(),"version",0,"body",Map.of("work","参与任务","taskIds",List.of(first,second)))).get("id").asText();
        assertEquals(2,db.count("SELECT count(*) FROM log_tasks WHERE log_id=?",id));
        call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        db.update("UPDATE tasks SET phase='ACCEPTED' WHERE id=?",first);
        db.update("UPDATE tasks SET phase='FEEDBACK' WHERE id=?",second);
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","继续记录","taskIds",List.of(first,second),"version",2));
        assertEquals(List.of(first,second),db.read(row(id).get("body")).get("taskIds"));
        assertEquals(List.of(first,second),db.read(db.one("SELECT body FROM log_versions WHERE log_id=? AND version=3",id).get("body")).get("taskIds"));
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","省略保留","version",3));
        assertEquals(2,db.count("SELECT count(*) FROM log_tasks WHERE log_id=?",id));
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","明确清空","taskIds",List.of(),"version",4));
        assertEquals(0,db.count("SELECT count(*) FROM log_tasks WHERE log_id=?",id));
    }
    @Test void invalidSelectionsAndStaleVersionsLeaveContentAndLinksUnchanged() throws Exception {
        String pending=task(employee,"RECEIVED"),unreceived=task(employee,"DISPATCHED"),done=task(employee,"ACCEPTED"),others=task(colleague,"RECEIVED"),feedback=task(employee,"FEEDBACK");
        String id=draft(today());call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        for(String task:List.of(unreceived,done,feedback)) call(400,"PUT","/logs/"+id+"/content",employee,Map.of("work","无效新增","taskIds",List.of(task),"version",2));
        call(400,"PUT","/logs/"+id+"/content",employee,Map.of("work","无效数组","taskIds",pending,"version",2));
        call(400,"PUT","/logs/draft",employee,Map.of("businessDate",today().minusDays(1).toString(),"version",0,"body",Map.of("work","不能保存未接收任务","taskIds",List.of(unreceived))));
        assertEquals(0,db.count("SELECT count(*) FROM daily_logs WHERE owner_id=? AND business_date=?::date",employee,today().minusDays(1).toString()));
        call(404,"PUT","/logs/"+id+"/content",employee,Map.of("work","越权新增","taskIds",List.of(others),"version",2));
        String managed=task(colleague,"RECEIVED");
        String managerLog=call(200,"PUT","/logs/draft",director,Map.of("businessDate",today().toString(),"version",0,"body",Map.of("work","管理者日志"))).get("id").asText();
        call(200,"POST","/logs/"+managerLog+"/submit",director,Map.of("version",1));
        call(403,"PUT","/logs/"+managerLog+"/content",director,Map.of("work","可读但未参与","taskIds",List.of(managed),"version",2));
        call(409,"PUT","/logs/"+id+"/content",employee,Map.of("work","过期版本","taskIds",List.of(pending),"version",1));
        assertEquals(2,row(id).get("version"));assertEquals("原始正文",db.read(row(id).get("body")).get("work"));
        assertEquals(0,db.count("SELECT count(*) FROM log_tasks WHERE log_id=?",id));
        assertEquals(1,db.count("SELECT count(*) FROM log_versions WHERE log_id=?",id));
    }
    @Test void firstSubmissionAllowsThreeShanghaiDatesOnly() throws Exception {
        for(int offset:List.of(-3,-2,-1,0,1)){
            String id=draft(today().plusDays(offset));
            boolean valid=offset>=-2&&offset<=0;
            var result=call(valid?200:400,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
            if(!valid){assertEquals("FIRST_SUBMISSION_WINDOW",result.get("code").asText());assertEquals(1,row(id).get("version"));}
            assertEquals(valid,row(id).get("submitted"));
            assertEquals(valid?1:0,db.count("SELECT count(*) FROM log_versions WHERE log_id=?",id));
        }
    }
    @Test void directEditPreservesFirstTimestampOtherFieldsAndChecksActorVersion() throws Exception {
        String id=draft(today());
        call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        Object first=row(id).get("submitted_at");
        call(403,"PUT","/logs/"+id+"/content",admin,Map.of("work","管理员不能代改","version",2));
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","新正文","version",2));
        assertEquals("VERSION_CONFLICT",call(409,"PUT","/logs/"+id+"/content",employee,Map.of("work","旧版覆盖","version",2)).get("code").asText());
        assertEquals(first,row(id).get("submitted_at"));assertEquals(true,row(id).get("submitted"));
        assertEquals(Map.of("work","新正文","tomorrow","保留其他历史字段"),db.read(row(id).get("body")));
        assertEquals(2,call(200,"GET","/logs/"+id+"/versions",employee,null).size());
        assertEquals(0,db.count("SELECT count(*) FROM review_requests WHERE target_id=?",id));
        assertEquals(1,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='LOG_CONTENT_UPDATED'",id));
        call(400,"PUT","/logs/"+id+"/content",employee,Map.of("work"," ","version",3));
        call(400,"PUT","/logs/"+id+"/content",employee,Map.of("work","伪造时间","version",3,"submittedAt",Instant.now().toString()));
        assertEquals(3,row(id).get("version"));
    }
    @Test void editWindowMayCrossThreeDayRangeButExpiresAtTwentyFourHours() throws Exception {
        String id=draft(today().minusDays(2));call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        db.update("UPDATE daily_logs SET business_date=?::date,submitted_at=now()-interval '23 hours' WHERE id=?",today().minusDays(3).toString(),id);
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","跨三日仍可编辑","version",2));
        db.update("UPDATE daily_logs SET submitted_at=now()-interval '24 hours' WHERE id=?",id);
        assertEquals("LOG_EDIT_WINDOW_EXPIRED",call(409,"PUT","/logs/"+id+"/content",employee,Map.of("work","过期覆盖","version",3)).get("code").asText());
        call(200,"POST","/logs/"+id+"/comments",director,Map.of("text","正文锁定后仍可评论"));
        assertEquals("跨三日仍可编辑",db.read(row(id).get("body")).get("work"));
    }
    @Test void removedRoutesAreAbsentFromRuntimeContractAndCannotWrite() throws Exception {
        String id=draft(today());call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        assertEquals("array",call(200,"GET","/openapi",employee,null).at("/components/schemas/LogContentUpdate/properties/taskIds/type").asText());
        var before=row(id); long audit=db.count("SELECT count(*) FROM audit_records WHERE company_id=?",company);
        long outbox=db.count("SELECT count(*) FROM outbox_events WHERE company_id=?",company);
        for(String suffix:List.of("read","revisions","withdraw")){
            call(404,"POST","/logs/"+id+"/"+suffix,employee,Map.of("version",2,"work","不生效","reason","不生效"));
            assertFalse(call(200,"GET","/openapi",employee,null).get("paths").has("/api/logs/{id}/"+suffix));
        }
        assertEquals(before,row(id));assertEquals(audit,db.count("SELECT count(*) FROM audit_records WHERE company_id=?",company));
        assertEquals(outbox,db.count("SELECT count(*) FROM outbox_events WHERE company_id=?",company));
        assertEquals(0,db.count("SELECT count(*) FROM log_reads WHERE log_id=?",id));
    }
    @Test void historyWriteFailureRollsBackContentVersionAuditAndOutbox() throws Exception {
        String id=draft(today());call(200,"POST","/logs/"+id+"/submit",employee,Map.of("version",1));
        db.update("INSERT INTO log_versions(company_id,log_id,version,body) VALUES (?,?,3,'{}'::jsonb)",company,id);
        var actor=Actor.from(db.one("SELECT * FROM users WHERE id=?",employee));
        long outbox=db.count("SELECT count(*) FROM outbox_events WHERE company_id=?",company);
        assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->logs.updateContent(actor,id,Map.of("work","失败不能落库","version",2)));
        assertEquals(2,row(id).get("version"));assertEquals("原始正文",db.read(row(id).get("body")).get("work"));
        assertEquals(0,db.count("SELECT count(*) FROM audit_records WHERE object_id=? AND type='LOG_CONTENT_UPDATED'",id));
        assertEquals(outbox,db.count("SELECT count(*) FROM outbox_events WHERE company_id=?",company));
        db.update("DELETE FROM log_versions WHERE log_id=? AND version=3",id);
        call(200,"PUT","/logs/"+id+"/content",employee,Map.of("work","恢复成功","version",2));
    }
}
