package cn.workpanel.module.task;

import cn.workpanel.*;
import org.junit.jupiter.api.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 任务列表查询：范围条件、参数校验和字段白名单均在服务端执行。 */
class TaskQueryServiceTest {
    static final Actor LEADER=new Actor("leader","c1","LEADER","d1","t1",true,false,false,"ACTIVE");
    Db db; TaskQueryService service;

    @BeforeEach void setUp() { db=mock(Db.class); service=new TaskQueryService(db); }

    Map<String,Object> row() {
        var task=new LinkedHashMap<String,Object>();
        task.put("id","task-1"); task.put("issuer_id","leader"); task.put("title","查询任务");
        task.put("start_at","2026-10-20T09:00:00Z");
        task.put("deadline","2026-10-20T10:00:00Z"); task.put("version",3); task.put("created_at","2026-10-10T10:00:00Z");
        task.put("phase","ACCEPTED"); task.put("body","{\"progress\":\"done\"}");
        return task;
    }

    @Test void listUsesExplicitProjectionAndNeverLeaksLifecycleFields() {
        when(db.count(anyString(),any(Object[].class))).thenReturn(1L);
        when(db.rows(startsWith("SELECT t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at"),any(Object[].class))).thenReturn(List.of(row()));
        var result=service.list(LEADER,new TaskQueryService.Query(0,20,"查询",null,null,"day"));
        @SuppressWarnings("unchecked") var item=((List<Map<String,Object>>)result.get("items")).getFirst();
        assertEquals(Set.of("id","issuer_id","title","start_at","deadline","version","created_at","participants","label"),item.keySet());
        for(String hidden:List.of("phase","status","completion","progress","done","body","events")) assertFalse(item.containsKey(hidden),hidden);
        verify(db).count(contains("FROM tasks t WHERE"),any(Object[].class));
        verify(db).rows(startsWith("SELECT t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at"),any(Object[].class));
    }

    @Test void invalidPageOrDateDoesNotQueryTasks() {
        assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(-1,20,"",null,null,"day")));
        assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,"bad-date","day")));
        verifyNoInteractions(db);
    }

    @Test void ownerOutsideLeaderTeamIsForbiddenBeforeTaskQuery() {
        when(db.one(startsWith("SELECT * FROM users"),eq("carl"),eq("c1"))).thenReturn(Map.of("id","carl","company_id","c1","department_id","d1","team_id","t2"));
        var error=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"","carl",null,"day")));
        assertEquals("FORBIDDEN",error.code);
        verify(db,never()).count(anyString(),any(Object[].class));
        verify(db,never()).rows(contains("FROM tasks t"),any(Object[].class));
    }

    @Test void taskListViewCopiesOnlyContractColumns() {
        var item=TaskListView.of(row());
        assertEquals("task-1",item.get("id"));
        assertFalse(item.containsKey("phase"));
        assertFalse(item.containsKey("body"));
    }
}
