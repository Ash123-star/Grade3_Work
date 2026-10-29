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
    static final String FROM="2026-10-01T00:00:00+08:00",TO="2026-10-03T00:00:00+08:00";
    Db db; LogQueryService service;
    @BeforeEach void setUp() { db=mock(Db.class); service=new LogQueryService(db); }

    @Test void employeeCannotOpenSubordinateEntryBeforeQuery() {
        var error=assertThrows(ApiError.class,()->service.list(EMPLOYEE,new LogQueryService.Query(0,20,null,null,"day"),true));
        assertEquals("FORBIDDEN",error.code); verifyNoInteractions(db);
    }

    @Test void rangeOutsideOwnerIsForbiddenWithoutReturningLogs() {
        when(db.one(startsWith("SELECT * FROM users"),any(),any())).thenReturn(Map.of("id","other","company_id","c1","department_id","d1","team_id","t2","status","ACTIVE"));
        when(db.count(contains("reporting_relations"),any(Object[].class))).thenReturn(0L);
        var error=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,"other",null,null),true));
        assertEquals("FORBIDDEN",error.code);
        verify(db,never()).rows(contains("daily_logs"),any(Object[].class));
    }

    @Test void invalidDateDoesNotQueryLogs() {
        assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,"invalid","day"),false));
        verifyNoInteractions(db);
    }

    @Test void halfOpenRangeRequiresBothEndpoints() {
        var error=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,FROM,null),true));
        assertEquals("INVALID_RANGE",error.code);
        var onlyTo=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,null,TO),true));
        assertEquals("INVALID_RANGE",onlyTo.code);
        verifyNoInteractions(db);
    }

    @Test void rangeCannotBeCombinedWithDateOrPeriod() {
        var withDate=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,"2026-10-01","day",null,null,FROM,TO),true));
        assertEquals("INVALID_RANGE",withDate.code);
        var withPeriod=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,"month",null,null,FROM,TO),true));
        assertEquals("INVALID_RANGE",withPeriod.code);
        verifyNoInteractions(db);
    }

    @Test void rangeMustBeOrderedAndAlignedWithShanghaiMidnight() {
        var reversed=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,TO,FROM),true));
        assertEquals("INVALID_RANGE",reversed.code);
        var equal=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,FROM,FROM),true));
        assertEquals("INVALID_RANGE",equal.code);
        var midnight=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,FROM,"2026-10-03T09:30:00+08:00"),true));
        assertEquals("INVALID_RANGE",midnight.code);
        var zone=assertThrows(ApiError.class,()->service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,"2026-10-01","2026-10-03"),true));
        assertEquals("INVALID_RANGE",zone.code);
        verifyNoInteractions(db);
    }

    @Test void validRangeReachesRepositoryWithServerSideScope() {
        when(db.count(anyString(),any(Object[].class))).thenReturn(0L);
        when(db.rows(anyString(),any(Object[].class))).thenReturn(List.of());
        var result=service.list(LEADER,new LogQueryService.Query(0,20,null,null,null,null,null,FROM,TO),true);
        assertEquals(0L,result.get("total"));
        verify(db).count(contains("reporting_relations"),any(Object[].class));
        verify(db).count(contains("business_date>=?::date"),any(Object[].class));
        verify(db).count(contains("l.submitted"),any(Object[].class));
    }

    @Test void calendarRejectsNonManagerAndInvalidMonth() {
        assertEquals("FORBIDDEN",assertThrows(ApiError.class,()->service.calendar(EMPLOYEE,"other","2026-10")).code);
        assertEquals("INVALID_MONTH",assertThrows(ApiError.class,()->service.calendar(LEADER,"other","2026-13")).code);
        assertEquals("INVALID_MONTH",assertThrows(ApiError.class,()->service.calendar(LEADER,"other","2026-1")).code);
        assertEquals("INVALID_OWNER",assertThrows(ApiError.class,()->service.calendar(LEADER," ","2026-10")).code);
        verifyNoInteractions(db);
    }

    @Test void calendarRejectsSelfAndOutOfScopeMember() {
        when(db.one(startsWith("SELECT * FROM users"),any(),any())).thenReturn(Map.of("id","leader","company_id","c1","department_id","d1","team_id","t1","status","ACTIVE"));
        assertEquals("FORBIDDEN",assertThrows(ApiError.class,()->service.calendar(LEADER,"leader","2026-10")).code);
        when(db.one(startsWith("SELECT * FROM users"),any(),any())).thenReturn(Map.of("id","other","company_id","c1","department_id","d2","team_id","t2","status","ACTIVE"));
        assertEquals("FORBIDDEN",assertThrows(ApiError.class,()->service.calendar(LEADER,"other","2026-10")).code);
    }
}
