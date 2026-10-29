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
