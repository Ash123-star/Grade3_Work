package cn.workpanel.module.log.application;

import cn.workpanel.*;
import cn.workpanel.module.review.application.ReviewApplicationService;
import org.junit.jupiter.api.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 日报工作流的无容器分支测试：版本、历史和草稿私密性。 */
class LogWorkflowServiceTest {
    static final Actor ALICE=new Actor("alice","c1","EMPLOYEE","d1","t1",false,false,false,"ACTIVE");
    Db db; Business business; ReviewApplicationService reviews; LogWorkflowService service;

    @BeforeEach void setUp() {
        db=mock(Db.class); business=mock(Business.class); reviews=mock(ReviewApplicationService.class); service=new LogWorkflowService(db,business,reviews);
        when(db.write(any())).thenReturn("{}"); when(db.read(any())).thenReturn(Map.of("work","完成日报"));
    }

    Map<String,Object> log(boolean submitted,int version) {
        var value=new HashMap<String,Object>(); value.put("id","log-1"); value.put("owner_id","alice"); value.put("submitted",submitted); value.put("version",version); value.put("body","{}"); return value;
    }

    @Test void createsDailyDraftOnlyWithVersionZero() {
        when(db.rows(startsWith("SELECT * FROM daily_logs"),any(Object[].class))).thenReturn(List.of());
        when(business.log(any(),anyString(),eq(false))).thenReturn(log(false,1));
        service.saveDraft(ALICE,Map.of("businessDate","2026-10-15","version",0,"body",Map.of("work","完成日报")));
        verify(db).update(startsWith("INSERT INTO daily_logs"),any(Object[].class));
        verify(db).update(startsWith("DELETE FROM log_tasks"),eq("c1"),anyString());
    }

    @Test void staleDraftVersionDoesNotSyncLinksOrReadResult() {
        when(db.rows(startsWith("SELECT * FROM daily_logs"),any(Object[].class))).thenReturn(List.of(log(false,2)));
        when(db.update(startsWith("UPDATE daily_logs SET body"),any(Object[].class))).thenReturn(0);
        assertThrows(ApiError.class,()->service.saveDraft(ALICE,Map.of("businessDate","2026-10-15","version",1,"body",Map.of("work","旧版本"))));
        verify(db,never()).update(startsWith("DELETE FROM log_tasks"),any(Object[].class));
        verify(business,never()).log(any(),anyString(),anyBoolean());
    }

    @Test void submitWritesHistoryInSameWorkflow() {
        when(business.log(ALICE,"log-1",true)).thenReturn(log(false,1));
        when(business.log(ALICE,"log-1",false)).thenReturn(log(true,2));
        when(db.update(startsWith("UPDATE daily_logs SET submitted"),any(Object[].class))).thenReturn(1);
        when(db.rows(startsWith("SELECT * FROM users WHERE company_id"),eq("c1"))).thenReturn(List.of());
        var result=service.submit(ALICE,"log-1",Map.of("version",1));
        verify(db).update(startsWith("INSERT INTO log_versions"),eq("c1"),eq("log-1"),eq(2),anyString());
        assertEquals("log-1",result.get("id"));
    }

    @Test void ownDraftCannotBeMarkedReadOrExposeComments() {
        when(business.log(ALICE,"log-1",false)).thenReturn(log(false,1));
        assertThrows(ApiError.class,()->service.markRead(ALICE,"log-1"));
        assertThrows(ApiError.class,()->service.comments(ALICE,"log-1"));
        verify(db,never()).update(startsWith("INSERT INTO log_reads"),any(Object[].class));
        verify(db,never()).rows(startsWith("SELECT id,actor_id,text"),any(Object[].class));
    }
}
