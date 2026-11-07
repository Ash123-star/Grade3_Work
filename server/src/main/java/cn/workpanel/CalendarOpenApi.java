package cn.workpanel;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.media.*;
import java.math.BigDecimal;
import java.util.List;

/** Calendar contracts extend task schemas without changing the shared draft. */
final class CalendarOpenApi {
    private CalendarOpenApi() { }

    static void register(Components components) {
        var legacy = components.getSchemas().get("TaskReschedule");
        components.addSchemas("TaskDeadlineReschedule", legacy);
        var move = OpenApi.object("version", "moveDays", "reason");
        move.addProperty("version", OpenApi.version().maximum(BigDecimal.valueOf(Integer.MAX_VALUE)));
        move.addProperty("moveDays", new IntegerSchema().format("int32")
                .minimum(BigDecimal.valueOf(Integer.MIN_VALUE)).maximum(BigDecimal.valueOf(Integer.MAX_VALUE))
                .description("非零整数日差；按上海业务日同时平移起止时间，保持时长"));
        move.addProperty("reason", OpenApi.text().minLength(1).maxLength(1000));
        components.addSchemas("TaskMoveReschedule", move);
        components.addSchemas("TaskReschedule", new ComposedSchema().oneOf(
                List.of(OpenApi.ref("TaskDeadlineReschedule"), OpenApi.ref("TaskMoveReschedule"))));
        var bounds = OpenApi.object("zone", "minDate", "maxDate", "revision", "maxRangeDays", "maxRecords", "maxPages");
        bounds.addProperty("zone", new StringSchema()._enum(List.of("Asia/Shanghai")));
        bounds.addProperty("minDate", new DateSchema());
        bounds.addProperty("maxDate", new DateSchema());
        bounds.addProperty("revision", OpenApi.text());
        for (String key : List.of("maxRangeDays", "maxRecords", "maxPages")) {
            bounds.addProperty(key, new IntegerSchema());
        }
        components.addSchemas("ScheduleConstraints", bounds);
        var capabilities = OpenApi.object("reschedule");
        capabilities.addProperty("reschedule", new BooleanSchema());
        components.getSchemas().get("TaskListItem").addProperty("capabilities", capabilities);
        var page = components.getSchemas().get("TaskPage");
        page.addProperty("snapshotToken", OpenApi.text().description("范围查询快照；新版月历后续页必须原样带回"));
        page.addProperty("scheduleConstraints", OpenApi.ref("ScheduleConstraints"));
        page.addProperty("nextCursor", OpenApi.text().nullable(true));
    }
}
