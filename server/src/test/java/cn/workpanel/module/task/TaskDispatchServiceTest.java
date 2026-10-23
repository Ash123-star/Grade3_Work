package cn.workpanel.module.task;

import cn.workpanel.Actor;
import cn.workpanel.ApiError;
import cn.workpanel.Db;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 派发服务分支：新建、重放、冲突、旧摘要兼容、校验失败不加锁。 */
class TaskDispatchServiceTest {
    static final Actor LEADER=new Actor("u-leader","c1","LEADER","d1","t1",true,false,false,"ACTIVE");
    static final ObjectMapper JSON=new ObjectMapper();
    static final Db REAL=new Db(null,JSON);
    Db db; TaskDispatchService service;

    static Map<String,Object> raw() { return new LinkedHashMap<>(Map.of("title","整理周报","ownerId","u-a","deadline","2026-10-20T18:00+08:00","collaborators",List.of("u-b"))); }
    static Map<String,Object> task(String id) { var t=new HashMap<String,Object>(Map.of("id",id,"owner_id","u-a","issuer_id","u-leader","title","整理周报","version",1)); t.put("body","{}"); return t; }

    @BeforeEach void setUp() {
        db=mock(Db.class); service=new TaskDispatchService(db);
        when(db.write(any())).thenAnswer(i->REAL.write(i.getArgument(0)));
        when(db.read(any())).thenReturn(Map.of());
        when(db.rows(startsWith("SELECT * FROM users"),any(),eq("c1"))).thenAnswer(i->List.of(Map.of("id",i.getArgument(1),"company_id","c1","department_id","d1","team_id","t1")));
        when(db.rows(startsWith("SELECT * FROM idempotency_keys"),any(Object[].class))).thenReturn(List.of());
        when(db.rows(startsWith("SELECT * FROM tasks WHERE id=? AND company_id=? AND issuer_id=?"),any(Object[].class))).thenAnswer(i->List.of(task(i.getArgument(1))));
    }

    static String code(Runnable r) { return assertThrows(ApiError.class,r::run).code; }

    @Test void createsTaskWithFixedInitialState() {
        var result=service.dispatch(LEADER,raw(),"k1");
        verify(db).one(contains("pg_advisory_xact_lock"),eq("u-leader:k1"));
        verify(db).update(contains("'DISPATCHED',1)"),any(),eq("c1"),eq("u-a"),eq("u-leader"),eq("整理周报"),isNull(),anyString(),anyString());
        verify(db).update(contains("INSERT INTO task_events"),any(Object[].class));
        verify(db).update(contains("INSERT INTO idempotency_keys"),eq("c1"),eq("u-leader"),eq("k1"),anyString(),anyString());
        assertFalse(result.containsKey("phase")); assertTrue(result.containsKey("events"));
    }

    @Test void replaySkipsSideEffects() {
        var d=TaskDraftNormalizer.normalize(raw());
        when(db.rows(startsWith("SELECT * FROM idempotency_keys"),any(Object[].class))).thenReturn(List.of(Map.of("request_hash",TaskDraftNormalizer.hash(REAL,d),"task_id","task0","hash_version",(short)2)));
        var result=service.dispatch(LEADER,raw(),"k1");
        assertEquals("task0",result.get("id"));
        verify(db,never()).update(anyString(),any(Object[].class));
        verify(db,never()).notify(any(),any(),any(),any(),any());
    }

    @Test void replayWithReorderedListsMatches() {
        var first=raw(); first.put("collaborators",List.of("u-b","u-c"));
        when(db.rows(startsWith("SELECT * FROM idempotency_keys"),any(Object[].class))).thenReturn(List.of(Map.of("request_hash",TaskDraftNormalizer.hash(REAL,TaskDraftNormalizer.normalize(first)),"task_id","task0","hash_version",2)));
        var again=raw(); again.put("collaborators",List.of("u-c","u-a","u-b","u-c"));
        assertEquals("task0",service.dispatch(LEADER,again,"k1").get("id"));
    }

    @Test void differentContentConflicts() {
        when(db.rows(startsWith("SELECT * FROM idempotency_keys"),any(Object[].class))).thenReturn(List.of(Map.of("request_hash","other","task_id","task0","hash_version",2)));
        assertEquals("IDEMPOTENCY_CONFLICT",code(()->service.dispatch(LEADER,raw(),"k1")));
        verify(db,never()).update(anyString(),any(Object[].class));
    }

    @Test void legacyRecordComparedWithLegacyHash() {
        var r=raw(); r.put("collaborators",List.of("u-c","u-b"));
        when(db.rows(startsWith("SELECT * FROM idempotency_keys"),any(Object[].class))).thenReturn(List.of(Map.of("request_hash",TaskDraftNormalizer.legacyHash(REAL,r),"task_id","task0","hash_version",1)));
        assertEquals("task0",service.dispatch(LEADER,r,"k1").get("id"));
        var reordered=raw(); reordered.put("collaborators",List.of("u-b","u-c"));
        assertEquals("IDEMPOTENCY_CONFLICT",code(()->service.dispatch(LEADER,reordered,"k1")));
    }

    @Test void validationFailuresDoNotLock() {
        assertEquals("IDEMPOTENCY_REQUIRED",code(()->service.dispatch(LEADER,raw(),null)));
        assertEquals("IDEMPOTENCY_REQUIRED",code(()->service.dispatch(LEADER,raw()," ")));
        assertEquals("IDEMPOTENCY_REQUIRED",code(()->service.dispatch(LEADER,raw(),"k".repeat(129))));
        var bad=raw(); bad.put("phase","ACCEPTED"); assertEquals("SERVER_MANAGED_FIELD",code(()->service.dispatch(LEADER,bad,"k1")));
        var employee=new Actor("u-e","c1","EMPLOYEE","d1","t1",true,false,false,"ACTIVE");
        assertEquals("FORBIDDEN",code(()->service.dispatch(employee,raw(),"k1")));
        var disabled=new Actor("u-l2","c1","LEADER","d1","t1",false,false,false,"ACTIVE");
        assertEquals("FORBIDDEN",code(()->service.dispatch(disabled,raw(),"k1")));
        verify(db,never()).one(contains("pg_advisory_xact_lock"),any(Object[].class));
        verify(db,never()).update(anyString(),any(Object[].class));
    }
}
