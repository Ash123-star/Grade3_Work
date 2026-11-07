package cn.workpanel.module.task;

import cn.workpanel.ApiError;
import org.junit.jupiter.api.Test;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class TaskScheduleTest {
    @Test void movesWholeIntervalWithoutChangingWallTimeOrDuration() {
        var moved=TaskSchedule.move("2026-11-02T09:00+08:00","2026-11-04T18:00+08:00",2);
        assertEquals("2026-11-04T09:00+08:00",moved.startAt());
        assertEquals("2026-11-06T18:00+08:00",moved.deadline());
        assertEquals(Duration.ofHours(57),Duration.between(OffsetDateTime.parse(moved.startAt()),OffsetDateTime.parse(moved.deadline())));
    }
    @Test void nullStartLeapYearAndYearBoundary() {
        assertNull(TaskSchedule.move(null,"2028-02-28T18:00+08:00",1).startAt());
        assertEquals("2028-02-29T18:00+08:00",TaskSchedule.move(null,"2028-02-28T18:00+08:00",1).deadline());
        assertEquals("2027-01-01T18:00+08:00",TaskSchedule.move(null,"2026-12-31T18:00+08:00",1).deadline());
        assertEquals("2026-12-31T18:00+08:00",TaskSchedule.move(null,"2027-01-01T18:00+08:00",-1).deadline());
    }
    @Test void rejectsInvalidSourceZeroAndOverflow() {
        for(String start:List.of("2026-11-04T18:00+08:00","2026-11-05T18:00+08:00","bad"))
            assertThrows(ApiError.class,()->TaskSchedule.move(start,"2026-11-04T18:00+08:00",1));
        assertThrows(ApiError.class,()->TaskSchedule.move(null,"2026-11-04T18:00+08:00",0));
        assertThrows(ApiError.class,()->TaskSchedule.move(null,"9999-12-31T18:00+08:00",1));
        assertThrows(ApiError.class,()->TaskSchedule.move(null,"2026-11-04T18:00+08:00",Integer.MAX_VALUE));
        assertThrows(ApiError.class,()->TaskSchedule.move(null,"2026-11-04T18:00",1));
    }
    @Test void strictTypesReasonCodePointsAndKeyBoundaries() {
        for(Object value:List.of("2",true,2.0,2147483648L,0))assertThrows(ApiError.class,()->TaskSchedule.integer(value,true,"INVALID_VERSION"));
        assertEquals(-2,TaskSchedule.integer(-2,false,"INVALID_MOVE_DAYS"));
        String emoji="😀";
        assertEquals(emoji.repeat(1000),TaskSchedule.reason("\u00a0"+emoji.repeat(1000)+"\u3000"));
        assertThrows(ApiError.class,()->TaskSchedule.reason(emoji.repeat(1001)));
        assertThrows(ApiError.class,()->TaskSchedule.reason("\u00a0\u3000"));
        TaskSchedule.key("a".repeat(128));
        for(String key:List.of("a".repeat(129),"a b","a\n","中文",""))assertThrows(ApiError.class,()->TaskSchedule.key(key));
        assertEquals("VERSION_EXHAUSTED",assertThrows(ApiError.class,()->TaskSchedule.nextVersion(Integer.MAX_VALUE)).code);
    }
    @Test void constraintsAreInclusiveAndYearScoped() {
        var c=new ScheduleConstraints(true,Clock.fixed(Instant.parse("2026-11-02T00:00:00Z"),ZoneOffset.UTC));
        assertEquals("2024-01-01",c.view().get("minDate"));assertEquals("2034-01-01",c.view().get("maxDate"));
        c.validate("2024-01-01T00:00+08:00","2034-01-01T23:59+08:00");
        assertThrows(ApiError.class,()->c.validate(null,"2034-01-02T00:00+08:00"));
        assertThrows(ApiError.class,()->c.match(null));
        assertEquals("SCHEDULE_CONSTRAINTS_CHANGED",assertThrows(ApiError.class,()->c.match("calendar-v1-2025")).code);
        var next=new ScheduleConstraints(true,Clock.fixed(Instant.parse("2026-12-31T16:00:00Z"),ZoneOffset.UTC));
        assertEquals("calendar-v1-2027",next.revision());
    }
    @Test void rangeRequiresTimezoneOrderedEndpointsAndFiniteBudget() {
        TaskQueryService.range("2026-11-01T00:00+08:00","2027-01-02T00:00+08:00");
        for(String[] bounds:List.of(new String[]{null,"2026-11-01T00:00Z"},new String[]{"2026-11-01","2026-12-01"},new String[]{"2026-12-01T00:00Z","2026-11-01T00:00Z"},new String[]{"2026-11-01T00:00Z","2027-01-03T00:00Z"}))
            assertThrows(ApiError.class,()->TaskQueryService.range(bounds[0],bounds[1]));
    }
}
