package cn.workpanel.module.task;

import cn.workpanel.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.time.*;
import java.util.*;

/** 默认关闭；全部审核消费者兼容 MOVE 后才启用。 */
@Component
public class ScheduleConstraints {
    private final boolean enabled;
    private final Clock clock;
    @Autowired public ScheduleConstraints(@Value("${workpanel.calendar.move-enabled:false}") boolean enabled) { this(enabled,Clock.systemUTC()); }
    public ScheduleConstraints(boolean enabled,Clock clock) { this.enabled=enabled;this.clock=clock; }
    public boolean enabled() { return enabled; }
    private int year() { return LocalDate.now(clock.withZone(TaskSchedule.ZONE)).getYear(); }
    public String revision() { return "calendar-v1-"+year(); }
    public Map<String,Object> view() { int year=year(); return Map.of("zone","Asia/Shanghai","minDate",LocalDate.of(year-2,1,1).toString(),"maxDate",LocalDate.of(year+8,1,1).toString(),"revision","calendar-v1-"+year,"maxRangeDays",62,"maxRecords",5000,"maxPages",200); }
    public void match(String revision) {
        if(revision==null || !revision.matches("calendar-v[0-9]+-[0-9]{4}")) throw ApiError.bad("INVALID_SCHEDULE_CONSTRAINTS","需要有效排期约束版本");
        if(!revision().equals(revision)) throw new ApiError(409,"SCHEDULE_CONSTRAINTS_CHANGED","排期范围已变化，请刷新后重新确认");
    }
    public void validate(String start,String end) {
        int year=year();
        for(String value:Arrays.asList(start,end)) if(value!=null && !value.isBlank()) {
            try {
                var date=OffsetDateTime.parse(value).atZoneSameInstant(TaskSchedule.ZONE).toLocalDate();
                if(date.isBefore(LocalDate.of(year-2,1,1))||date.isAfter(LocalDate.of(year+8,1,1))) throw new IllegalArgumentException();
            } catch(RuntimeException e) { throw ApiError.bad("INVALID_DATE","排期日期不在服务端支持范围内"); }
        }
    }
    public boolean mayMove(Actor actor,Map<String,Object> task) {
        return enabled && actor.status().equals("ACTIVE") && !actor.mustChange() && actor.manager() && actor.dispatch() &&
            (actor.admin()||actor.id().equals(Db.str(task,"issuer_id"))) && !Set.of("ARCHIVED","WITHDRAWN").contains(Db.str(task,"phase"));
    }
}
