package cn.workpanel;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.media.*;
import java.util.*;

/** P0移动端新增响应模式；从运行时SpringDoc导出，仓库快照在统一验收时再生成。 */
final class MobileP0OpenApi {
    private MobileP0OpenApi() { }
    static void register(Components c) {
        var confirmation=new ObjectSchema(); confirmation.setAdditionalProperties(true);
        for(String key:List.of("id","kind","target_id","status","decision_source")) confirmation.addProperty(key,OpenApi.text());
        confirmation.addProperty("decision_source",OpenApi.text().nullable(true));
        confirmation.setDescription("TASK_CREATE审核结果；id为申请ID，target_id为任务ID，只有审核生效后任务才存在。创始人免审同样返回审核记录。");
        c.addSchemas("AiTaskConfirmationResult",confirmation);
        var team=OpenApi.object("id","name","department_id","version");
        for(String key:List.of("id","name","department_id")) team.addProperty(key,OpenApi.text()); team.addProperty("version",OpenApi.version());
        c.addSchemas("TeamDirectory",new ArraySchema().items(team));
        var card=OpenApi.object("id","title","version","phase","dispatchAt","participants");
        for(String key:List.of("id","title","phase")) card.addProperty(key,OpenApi.text());
        for(String key:List.of("start_at","deadline","created_at","dispatchAt")) card.addProperty(key,new DateTimeSchema().nullable(true));
        card.addProperty("version",OpenApi.version()); card.addProperty("participants",new ArraySchema().items(OpenApi.ref("TaskParticipant"))); card.addProperty("label",OpenApi.ref("TaskLabel"));
        c.addSchemas("ReceivedTaskCard",card); c.addSchemas("ReceivedTaskPage",page("ReceivedTaskCard")); c.addSchemas("TaskPage",page("TaskListItem"));
        var content=OpenApi.object("work","version"); content.addProperty("work",OpenApi.text().minLength(1)); content.addProperty("version",OpenApi.version()); c.addSchemas("LogContentUpdate",content);
        var calendar=OpenApi.object("ownerId","month","days","employmentStartDate","logIds");
        calendar.addProperty("ownerId",OpenApi.text()); calendar.addProperty("month",new StringSchema().pattern("^\\d{4}-\\d{2}$")); calendar.addProperty("employmentStartDate",new DateSchema().nullable(true));
        var days=new ObjectSchema(); days.setAdditionalProperties(new StringSchema()._enum(List.of("SUBMITTED","MISSING","FUTURE","UNKNOWN"))); calendar.addProperty("days",days);
        var logIds=new ObjectSchema(); logIds.setAdditionalProperties(new StringSchema()); calendar.addProperty("logIds",logIds); c.addSchemas("MemberLogCalendar",calendar);
        var profile=OpenApi.object("version"); profile.addProperty("version",OpenApi.version());
        profile.addProperty("introduction",OpenApi.text().nullable(true)); profile.addProperty("avatarAttachmentId",OpenApi.text().maxLength(200).nullable(true));
        profile.addProperty("phone",new StringSchema().nullable(true).pattern("^1[3-9][0-9]{9}$")); profile.addProperty("email",new StringSchema().nullable(true).format("email").maxLength(320));
        profile.addProperty("gender",new StringSchema().nullable(true).maxLength(32)); profile.addProperty("age",new IntegerSchema().minimum(java.math.BigDecimal.ZERO).nullable(true)); c.addSchemas("Profile",profile);
        var profileView=new ObjectSchema(); profileView.setAdditionalProperties(true);
        for(String key:List.of("id","name","role","status")) profileView.addProperty(key,OpenApi.text());
        for(String key:List.of("phone","email","gender","age")) profileView.addProperty(key,profile.getProperties().get(key));
        profileView.addProperty("version",OpenApi.version()); profileView.addProperty("employmentStartDate",new DateSchema().nullable(true));
        c.addSchemas("ProfileView",profileView);
        var metric=OpenApi.object("numerator","denominator","rate","definition","denominatorKnown");
        metric.addProperty("numerator",new IntegerSchema().format("int64")); metric.addProperty("denominator",new IntegerSchema().format("int64")); metric.addProperty("rate",new NumberSchema().nullable(true)); metric.addProperty("definition",OpenApi.text()); metric.addProperty("denominatorKnown",new BooleanSchema()); c.addSchemas("AnalyticsMetric",metric);
        var group=new ObjectSchema(); group.setAdditionalProperties(true); group.addProperty("groupId",OpenApi.text()); group.addProperty("groupName",OpenApi.text());
        var trend=new ObjectSchema(); trend.setAdditionalProperties(true); trend.addProperty("date",new DateSchema());
        var summary=OpenApi.object("range","updatedAt","filters","groupBy","groupedComparison","taskPhaseDistribution","trend");
        for(String key:List.of("dispatched","received","feedback","accepted","overdue","diarySubmitted","onTimeAcceptance")) {
            group.addProperty(key,new IntegerSchema().format("int64")); trend.addProperty(key,new IntegerSchema().format("int64"));
            if(!key.equals("onTimeAcceptance")) summary.addProperty(key,new IntegerSchema().format("int64"));
        }
        for(String key:List.of("onTimeAccepted","onTimeDenominator","diaryDenominator")) group.addProperty(key,new IntegerSchema().format("int64"));
        for(String key:List.of("onTimeRate","diaryRate")) group.addProperty(key,new NumberSchema().nullable(true));
        group.addProperty("diaryDenominatorKnown",new BooleanSchema());
        trend.addProperty("diaryDenominator",new IntegerSchema().format("int64")); trend.addProperty("diaryRate",new NumberSchema().nullable(true)); trend.addProperty("diaryDenominatorKnown",new BooleanSchema());
        c.addSchemas("AnalyticsGroup",group); c.addSchemas("AnalyticsTrendPoint",trend);
        var phase=OpenApi.object("phase","phaseCode","count"); phase.addProperty("phase",OpenApi.text()); phase.addProperty("phaseCode",OpenApi.text()); phase.addProperty("count",new IntegerSchema().format("int64")); c.addSchemas("TaskPhaseCount",phase);
        var filters=new ObjectSchema(); filters.setAdditionalProperties(true); summary.addProperty("filters",filters); summary.addProperty("range",new ObjectSchema().additionalProperties(true)); summary.addProperty("updatedAt",new DateTimeSchema()); summary.addProperty("groupBy",new StringSchema()._enum(List.of("department","team","person")));
        summary.addProperty("onTimeAcceptance",OpenApi.ref("AnalyticsMetric")); summary.addProperty("dailySubmission",OpenApi.ref("AnalyticsMetric"));
        for(String key:List.of("groupedComparison","departmentComparison","departmentDistribution")) summary.addProperty(key,new ArraySchema().items(OpenApi.ref("AnalyticsGroup")));
        for(String key:List.of("trend","dailyTrend")) summary.addProperty(key,new ArraySchema().items(OpenApi.ref("AnalyticsTrendPoint")));
        summary.addProperty("taskPhaseDistribution",new ArraySchema().items(OpenApi.ref("TaskPhaseCount"))); summary.addProperty("definition",OpenApi.text()); c.addSchemas("AnalyticsSummary",summary);
        var detail=OpenApi.object("id","resource","title","owner_id","owner_name","version","group_id","group_name","occurred_at","bucket");
        for(String key:List.of("id","title","owner_id","owner_name","group_id","group_name")) detail.addProperty(key,OpenApi.text());
        detail.addProperty("resource",new StringSchema()._enum(List.of("tasks","logs"))); detail.addProperty("phase",new StringSchema().nullable(true));
        detail.addProperty("version",OpenApi.version()); detail.addProperty("deadline",new DateTimeSchema().nullable(true)); detail.addProperty("occurred_at",new DateTimeSchema()); detail.addProperty("bucket",new DateSchema()); c.addSchemas("AnalyticsDetail",detail);
        var details=page("AnalyticsDetail"); details.addProperty("metric",OpenApi.text()); details.addProperty("groupBy",OpenApi.text()); details.addProperty("range",new ObjectSchema().additionalProperties(true)); details.addProperty("filters",filters); c.addSchemas("AnalyticsDetailsPage",details);
    }
    private static ObjectSchema page(String item) {
        var page=OpenApi.object("items","total","nextCursor"); page.addProperty("items",new ArraySchema().items(OpenApi.ref(item))); page.addProperty("total",new IntegerSchema().format("int64")); page.addProperty("nextCursor",new StringSchema()); return page;
    }
}
