package cn.workpanel.module.log.application;

import cn.workpanel.*;
import org.junit.jupiter.api.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/** 下属日报入口在查询前拒绝员工，且范围条件始终由服务端生成。 */
class LogQueryServiceTest {
    static final Actor EMPLOYEE=new Actor("alice","c1","EMPLOYEE","d1","t1",false,false,false,"ACTIVE");
    static final Actor LEADER=new Actor("leader","c1","LEADER","d1","t1",true,false,false,"ACTIVE");
    Db db; LogQueryService service;
    @BeforeEach void setUp() { db=mock(Db.class); service=new LogQueryService(db); }

    @Test void employeeCannotOpenSubordinateEntryBeforeQuery() {
        var error=assertThrows(ApiError.class,()->service.list(EMPLOYEE,new LogQueryService.Query(0,20,null,null,"day"),true));
        assertEquals("FORBIDDEN",error.code); verifyNoInteractions(db);
    }

    @Test void rangeOutsideOwnerIsForbiddenWithoutReturningLogs() {
        when(db.one(startsWith("SELECT * FROM users"),any(),any())).thenReturn(Map.of("id","other","company_id","c1","department_id","d1","team_id","t2"));
        var error=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,"other",null,"day"),true));
        assertEquals("FORBIDDEN",error.code); verify(db,never()).count(anyString(),any(Object[].class));
    }

    @Test void invalidDateDoesNotQueryLogs() {
        assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,"invalid","day"),false));
        verifyNoInteractions(db);
    }
}
