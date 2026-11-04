package cn.workpanel.module.personaltodo.api;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.*;
import java.util.List;

/** Personal-todo v1 HTTP shapes; dates are Shanghai civil dates, timestamps UTC. */
public final class TodoContracts {
    private TodoContracts() {}
    @Schema(name="PersonalTodo")
    public record Todo(String id,String title,String note,LocalDate date,boolean completed,
                       Instant completedAt,int version,Instant createdAt,Instant updatedAt) {}
    @Schema(name="PersonalTodoDayCount") public record DayCount(LocalDate date,long total,long completed) {}
    @Schema(name="PersonalTodoCalendar") public record Calendar(String month,LocalDate fromDate,LocalDate toDate,List<DayCount> days) {}
    @Schema(name="PersonalTodoPage") public record Page(List<Todo> items,long total,String nextCursor) {}
    @Schema(name="PersonalTodoDeleted") public record Deleted(String id,boolean deleted,int version) {}
    @Schema(name="PersonalTodoCreate",additionalProperties=Schema.AdditionalPropertiesValue.FALSE)
    public record Create(@Schema(minLength=1,maxLength=120,requiredMode=Schema.RequiredMode.REQUIRED) String title,
                         @Schema(maxLength=2000) String note,
                         @Schema(format="date",requiredMode=Schema.RequiredMode.REQUIRED) String date) {}
    @Schema(name="PersonalTodoUpdate",additionalProperties=Schema.AdditionalPropertiesValue.FALSE)
    public record Update(@Schema(minLength=1,maxLength=120,requiredMode=Schema.RequiredMode.REQUIRED) String title,
                         @Schema(maxLength=2000) String note,
                         @Schema(format="date",requiredMode=Schema.RequiredMode.REQUIRED) String date,
                         @Schema(requiredMode=Schema.RequiredMode.REQUIRED) boolean completed,
                         @Schema(minimum="1",requiredMode=Schema.RequiredMode.REQUIRED) int version) {}
}
