package cn.workpanel.module.task;

import cn.workpanel.*;
import org.junit.jupiter.api.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 任务列表查询：范围条件、时间区间相交、参数校验和字段白名单均在服务端执行。 */
class TaskQueryServiceTest {
    static final Actor LEADER=new Actor("leader","c1","LEADER","d1","t1",true,false,false,"ACTIVE");
    Db db; TaskQueryService service;
    final List<String> sql=new ArrayList<>(); final List<List<Object>> args=new ArrayList<>();

    @BeforeEach void setUp() { db=mock(Db.class); service=new TaskQueryService(db); }

    void record() { record(statement->List.of()); }

    /** 记录实际下发的 SQL 与参数，用于断言区间条件真正进入查询而不是留在请求对象里。 */
    void record(java.util.function.Function<String,List<Map<String,Object>>> pages) {
        org.mockito.stubbing.Answer<Object> answer=call->{
            String statement=call.getArgument(0);
            sql.add(statement);
            Object[] all=call.getArguments();
            args.add(all.length==2&&all[1] instanceof Object[] array?Arrays.asList(array):new ArrayList<>(Arrays.asList(all).subList(1,all.length)));
            return call.getMethod().getReturnType()==long.class?1L:pages.apply(statement);
        };
        when(db.count(anyString(),any(Object[].class))).thenAnswer(answer);
        when(db.rows(anyString(),any(Object[].class))).thenAnswer(answer);
    }

    Map<String,Object> row() {
        var task=new LinkedHashMap<String,Object>();
        task.put("id","task-1"); task.put("issuer_id","leader"); task.put("title","查询任务");
        task.put("start_at","2026-10-20T09:00:00Z");
        task.put("deadline","2026-10-20T10:00:00Z"); task.put("version",3); task.put("created_at","2026-10-10T10:00:00Z");
        task.put("phase","ACCEPTED"); task.put("body","{\"progress\":\"done\"}");
        return task;
    }

    Map<String,Object> card() {
        var task=new LinkedHashMap<String,Object>();
        task.put("id","task-1"); task.put("issuer_id","leader"); task.put("title","卡片任务"); task.put("start_at",null);
        task.put("deadline","2026-10-20T10:00:00Z"); task.put("phase","WITHDRAWN"); task.put("version",4);
        task.put("created_at","2026-10-10T10:00:00Z"); task.put("dispatch_at","2026-10-12T01:00:00Z");
        return task;
    }

    @Test void listUsesExplicitProjectionAndNeverLeaksLifecycleFields() {
        when(db.count(anyString(),any(Object[].class))).thenReturn(1L);
        when(db.rows(startsWith("SELECT t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at"),any(Object[].class))).thenReturn(List.of(row()));
        var result=service.list(LEADER,new TaskQueryService.Query(0,20,"查询",null,null,null));
        @SuppressWarnings("unchecked") var item=((List<Map<String,Object>>)result.get("items")).getFirst();
        assertEquals(Set.of("id","issuer_id","title","start_at","deadline","version","created_at","participants","label"),item.keySet());
        for(String hidden:List.of("phase","status","completion","progress","done","body","events")) assertFalse(item.containsKey(hidden),hidden);
        verify(db).count(contains("FROM tasks t WHERE"),any(Object[].class));
        verify(db).rows(startsWith("SELECT t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.version,t.created_at"),any(Object[].class));
    }

    @Test void explicitFromToSerializesHalfOpenIntersection() {
        record();
        service.list(LEADER,new TaskQueryService.Query(0,20,"",null,null,null,"2026-10-01T00:00:00+08:00","2026-11-01T00:00:00+08:00"));
        String countSql=sql.getFirst(); assertTrue(countSql.contains("COALESCE(t.start_at,t.deadline)<?::timestamptz"),countSql);
        assertTrue(countSql.contains("t.deadline>=?::timestamptz"),countSql);
        assertTrue(countSql.contains("t.start_at IS NULL OR t.start_at<=t.deadline"),countSql);
        List<Object> values=args.getFirst();
        assertEquals("2026-10-31T16:00:00Z",values.get(values.size()-2));
        assertEquals("2026-09-30T16:00:00Z",values.getLast());
    }

    @Test void invalidRangesAndParticipantAliasesAreRejectedBeforeQuerying() {
        var onlyFrom=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,null,"day","2026-10-01T00:00:00Z",null)));
        assertEquals("INVALID_RANGE",onlyFrom.code);
        var mixed=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,"2026-10-01","day","2026-10-01T00:00:00Z","2026-10-02T00:00:00Z")));
        assertEquals("INVALID_RANGE",mixed.code);
        var reversed=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,null,"day","2026-10-02T00:00:00Z","2026-10-01T00:00:00Z")));
        assertEquals("INVALID_RANGE",reversed.code);
        var same=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,null,"day","2026-10-01T00:00:00Z","2026-10-01T00:00:00Z")));
        assertEquals("INVALID_RANGE",same.code);
        var noZone=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,null,"day","2026-10-01T00:00:00","2026-10-02T00:00:00")));
        assertEquals("INVALID_RANGE",noZone.code);
        var longSearch=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"x".repeat(201),null,null,"day")));
        assertEquals("INVALID_SEARCH",longSearch.code);
        verifyNoInteractions(db);
    }

    @Test void invalidPageOrDateDoesNotQueryTasks() {
        assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(-1,20,"",null,null,"day")));
        assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"",null,"bad-date","day")));
        assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,101,"",null,null,"day")));
        verifyNoInteractions(db);
    }

    @Test void ownerOutsideLeaderTeamIsForbiddenBeforeTaskQuery() {
        when(db.one(startsWith("SELECT * FROM users"),eq("carl"),eq("c1"))).thenReturn(Map.of("id","carl","company_id","c1","department_id","d1","team_id","t2"));
        var error=assertThrows(ApiError.class,()->service.list(LEADER,new TaskQueryService.Query(0,20,"","carl",null,null)));
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

    @Test void receivedCardKeepsPhasesAndSortsByEarliestRealDispatch() {
        record(statement->statement.startsWith("SELECT t.id,t.issuer_id,t.title,t.start_at,t.deadline,t.phase")?List.of(card()):List.of());
        var result=service.receivedCard(LEADER,0,30,"卡片");
        String cardSql=sql.stream().filter(statement->statement.contains("dispatched.dispatch_at")).findFirst().orElseThrow();
        assertTrue(cardSql.contains("ORDER BY dispatched.dispatch_at DESC NULLS LAST,t.id"),cardSql);
        assertTrue(cardSql.contains("min(e.created_at) AS dispatch_at"),cardSql);
        assertTrue(cardSql.contains("e.type='DISPATCHED'"),cardSql);
        assertTrue(cardSql.contains("personal.user_id=?"),cardSql);
        assertTrue(cardSql.contains("personal.company_id=t.company_id"),cardSql);
        @SuppressWarnings("unchecked") var item=((List<Map<String,Object>>)result.get("items")).getFirst();
        assertEquals(Set.of("id","issuer_id","title","start_at","deadline","version","phase","created_at","dispatchAt","participants","label"),item.keySet());
        assertEquals("WITHDRAWN",item.get("phase"));
        assertEquals("2026-10-12T01:00:00Z",item.get("dispatchAt"));
        assertEquals("1",result.get("nextCursor"));
    }

    @Test void receivedCardRejectsOversizedSearchAndInvalidPage() {
        assertThrows(ApiError.class,()->service.receivedCard(LEADER,0,30,"x".repeat(201)));
        assertThrows(ApiError.class,()->service.receivedCard(LEADER,-1,30,""));
        assertThrows(ApiError.class,()->service.receivedCard(LEADER,0,0,""));
        verifyNoInteractions(db);
    }
}
