package cn.workpanel;

import io.swagger.v3.oas.models.*;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.media.*;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.security.*;
import org.springdoc.core.customizers.OpenApiCustomizer;
import org.springframework.context.annotation.*;
import java.util.*;

/** Map 边界仍拒绝未知字段；显式模式供 Flutter/Web 生成一致的请求模型。 */
@Configuration
public class OpenApi {
    static ObjectSchema object(String... required) { var s=new ObjectSchema(); s.setAdditionalProperties(false); if(required.length>0) s.setRequired(List.of(required)); return s; }
    static Schema<?> ref(String name) { return new Schema<>().$ref("#/components/schemas/"+name); }
    static StringSchema text() { var s=new StringSchema(); s.setMaxLength(20000); return s; }
    static IntegerSchema version() { var s=new IntegerSchema(); s.setMinimum(java.math.BigDecimal.ZERO); return s; }
    static ArraySchema ids() { var s=new ArraySchema(); s.setItems(new StringSchema()); s.setMaxItems(100); s.setUniqueItems(true); return s; }
    static ObjectSchema revision(String content,String key) { var s=object("version","reason",key); s.addProperty("version",version()); s.addProperty("reason",text().minLength(1)); s.addProperty(key,ref(content)); return s; }
    @Bean OpenAPI contract() {
        var c=new Components().addSecuritySchemes("bearer",new SecurityScheme().type(SecurityScheme.Type.HTTP).scheme("bearer").description("登录获取的不透明会话；改密或停用后撤销"));
        var registration=object("account","password","phone","name","departmentId");
        registration.addProperty("account",new StringSchema().pattern("^[a-zA-Z0-9_.-]{3,64}$")); registration.addProperty("password",text().minLength(12).description("UTF-8 编码不超过 72 字节")); registration.addProperty("phone",new StringSchema().pattern("^1[3-9][0-9]{9}$")); registration.addProperty("name",text().minLength(1)); registration.addProperty("departmentId",text().minLength(1)); c.addSchemas("Registration",registration);
        var login=object("account","password"); login.addProperty("account",text()); login.addProperty("password",text()); c.addSchemas("Login",login);
        var password=object("oldPassword","newPassword"); password.addProperty("oldPassword",text()); password.addProperty("newPassword",text().minLength(12)); c.addSchemas("PasswordChange",password);
        var task=object("title","ownerId","deadline"); task.addProperty("title",new StringSchema().minLength(1).maxLength(200)); task.addProperty("ownerId",text().minLength(1)); task.addProperty("deadline",new DateTimeSchema().description("含时区的 ISO8601 时间")); task.addProperty("urgency",new StringSchema()._enum(List.of("URGENT","NORMAL","LOW"))._default("NORMAL"));
        for(String field:List.of("group","content","progressNote")) task.addProperty(field,text()); task.addProperty("collaborators",ids()); task.addProperty("attachments",ids()); c.addSchemas("TaskDraft",task);
        c.addSchemas("TaskRevision",revision("TaskDraft","candidate"));
        var event=object("type","version"); event.addProperty("type",new StringSchema()._enum(List.of("RECEIVED","FEEDBACK","ACCEPTED","ARCHIVED","WITHDRAWN"))); event.addProperty("version",version()); event.addProperty("text",text().description("反馈/撤回必填")); c.addSchemas("TaskEvent",event);
        var log=object(); for(String field:List.of("work","blockers","tomorrow")) log.addProperty(field,text()); log.addProperty("hours",new NumberSchema().minimum(java.math.BigDecimal.ZERO).maximum(java.math.BigDecimal.valueOf(24))); log.addProperty("taskIds",ids()); c.addSchemas("LogContent",log);
        var draft=object("businessDate","body","version"); draft.addProperty("businessDate",new DateSchema()); draft.addProperty("body",ref("LogContent")); draft.addProperty("version",version()); c.addSchemas("LogDraft",draft); c.addSchemas("LogRevision",revision("LogContent","body"));
        var v=object("version"); v.addProperty("version",version()); c.addSchemas("Version",v);
        var comment=object("text"); comment.addProperty("text",text().minLength(1)); c.addSchemas("Comment",comment);
        var decision=object("approve"); decision.addProperty("approve",new BooleanSchema()); decision.addProperty("reason",text().description("驳回必填")); c.addSchemas("ReviewDecision",decision);
        var reviewer=object("version","reason"); reviewer.addProperty("version",version()); reviewer.addProperty("reason",text().minLength(1)); c.addSchemas("ReviewerApplication",reviewer);
        var membership=object("version","reason","departmentId"); membership.addProperty("version",version()); membership.addProperty("reason",text().minLength(1)); membership.addProperty("departmentId",text().minLength(1)); c.addSchemas("MembershipApplication",membership);
        var policy=object("version","reason"); policy.addProperty("version",version()); policy.addProperty("reason",text().minLength(1)); policy.addProperty("taskTeamReview",new BooleanSchema()); policy.addProperty("taskDepartmentReview",new BooleanSchema()); c.addSchemas("ReviewPolicy",policy);
        var organization=object("version","reason"); organization.addProperty("version",version()); organization.addProperty("reason",text().minLength(1)); for(String field:List.of("name","departmentId","teamId","managerId")) organization.addProperty(field,text()); organization.addProperty("role",new StringSchema()._enum(List.of("ADMIN","FOUNDER","DIRECTOR","LEADER","EMPLOYEE"))); organization.addProperty("status",new StringSchema()._enum(List.of("ACTIVE","DISABLED"))); organization.addProperty("dispatchEnabled",new BooleanSchema()); organization.addProperty("companyReviewer",new BooleanSchema()); c.addSchemas("UserRevision",organization);
        var unit=object("name","version","reason"); unit.addProperty("id",text()); unit.addProperty("name",text().minLength(1)); unit.addProperty("departmentId",text().description("团队必填")); unit.addProperty("version",version()); unit.addProperty("reason",text().minLength(1)); c.addSchemas("UnitRevision",unit);
        var item=object("title","version"); item.addProperty("id",text()); item.addProperty("title",text().minLength(1)); item.addProperty("text",text()); item.addProperty("version",version()); item.addProperty("pinned",new BooleanSchema()); item.addProperty("archived",new BooleanSchema()); item.addProperty("position",new IntegerSchema().minimum(java.math.BigDecimal.ZERO).maximum(java.math.BigDecimal.valueOf(10000))); c.addSchemas("PersonalItem",item);
        var company=object("title","version","reason"); company.setProperties(new LinkedHashMap<>(item.getProperties())); company.addProperty("reason",text().minLength(1)); c.addSchemas("CompanyItemRevision",company);
        var note=object("resource","objectId","text","version"); note.addProperty("resource",new StringSchema()._enum(List.of("tasks","dashboard/company"))); note.addProperty("objectId",text()); note.addProperty("text",text()); note.addProperty("version",version()); c.addSchemas("PrivateNote",note);
        var profile=object("version"); profile.addProperty("version",version()); profile.addProperty("avatarAttachmentId",text()); profile.addProperty("introduction",text()); c.addSchemas("Profile",profile);
        var job=object("date","period"); job.addProperty("date",new DateSchema()); job.addProperty("period",new StringSchema()._enum(List.of("day","week","month"))); job.addProperty("purpose",new StringSchema()._enum(List.of("SUMMARY","EXPLAIN_RISK","SPLIT_STEPS","DRAFT_TASK"))); job.addProperty("focusSourceId",text().description("非 SUMMARY 操作必填，且须为当前范围内来源")); c.addSchemas("AiJobRequest",job);
        var confirm=object("actionIndex","task"); confirm.addProperty("actionIndex",new IntegerSchema().minimum(java.math.BigDecimal.ZERO).maximum(java.math.BigDecimal.valueOf(2))); confirm.addProperty("task",ref("TaskDraft")); c.addSchemas("ConfirmTask",confirm);
        var node=object("title","type","sourceIds"); node.addProperty("title",text().minLength(1)); node.addProperty("type",new StringSchema()._enum(List.of("GOAL","RESULT","BLOCKER","RISK"))); node.addProperty("sourceIds",ids()); c.addSchemas("AiNode",node);
        var action=object("title","sourceIds"); action.addProperty("title",text().minLength(1)); action.addProperty("ownerId",text()); action.addProperty("sourceIds",ids()); c.addSchemas("AiAction",action);
        var aiDraft=object("version","summary","sourceIds","nodes","actions"); aiDraft.addProperty("version",version()); aiDraft.addProperty("summary",text().minLength(1)); aiDraft.addProperty("sourceIds",ids()); aiDraft.addProperty("nodes",new ArraySchema().items(ref("AiNode")).maxItems(10)); aiDraft.addProperty("actions",new ArraySchema().items(ref("AiAction")).maxItems(3)); c.addSchemas("AiDraftEdit",aiDraft);
        var edge=object("sourceId","targetId"); edge.addProperty("sourceId",text()); edge.addProperty("targetId",text()); edge.addProperty("label",text()); c.addSchemas("MapEdge",edge);
        var error=object("code","message","traceId"); for(String field:List.of("code","message","traceId")) error.addProperty(field,text()); c.addSchemas("Error",error);
        return new OpenAPI().servers(List.of(new io.swagger.v3.oas.models.servers.Server().url("/"))).info(new Info().title("企业协作智能面板 API").version("1.0.0").description("UTC 时间，Asia/Shanghai 业务日期，周一为周首。重要修改提交候选审核；任务列表不提供完成情况。分页 cursor 是非负偏移量。" )).components(c).addSecurityItem(new SecurityRequirement().addList("bearer"));
    }
    @Bean OpenApiCustomizer requestModels() {
        return api->{
            var bodies=Map.ofEntries(
                Map.entry("POST /api/auth/register","Registration"),Map.entry("POST /api/auth/login","Login"),Map.entry("POST /api/auth/password","PasswordChange"),
                Map.entry("POST /api/tasks","TaskDraft"),Map.entry("POST /api/tasks/{id}/events","TaskEvent"),Map.entry("POST /api/tasks/{id}/revisions","TaskRevision"),
                Map.entry("PUT /api/logs/draft","LogDraft"),Map.entry("POST /api/logs/{id}/submit","Version"),Map.entry("POST /api/logs/{id}/revisions","LogRevision"),Map.entry("POST /api/logs/{id}/comments","Comment"),
                Map.entry("POST /api/reviews/{id}/decision","ReviewDecision"),Map.entry("POST /api/organization/membership-application","MembershipApplication"),Map.entry("POST /api/organization/reviewer-application","ReviewerApplication"),Map.entry("POST /api/organization/review-policy/revisions","ReviewPolicy"),Map.entry("POST /api/organization/users/{id}/revisions","UserRevision"),Map.entry("POST /api/organization/{kind}/revisions","UnitRevision"),
                Map.entry("POST /api/dashboard/company/revisions","CompanyItemRevision"),Map.entry("POST /api/dashboard/personal","PersonalItem"),Map.entry("PUT /api/private-notes","PrivateNote"),Map.entry("PUT /api/profiles/me","Profile"),
                Map.entry("POST /api/ai/jobs","AiJobRequest"),Map.entry("PUT /api/ai/jobs/{id}/draft","AiDraftEdit"),Map.entry("POST /api/ai/jobs/{id}/confirm-task","ConfirmTask"),Map.entry("POST /api/ai-maps/edges","MapEdge"));
            api.getPaths().forEach((path,item)->item.readOperationsMap().forEach((method,op)->{
                String name=bodies.get(method.name()+" "+path); if(name!=null&&op.getRequestBody()!=null) op.getRequestBody().setContent(new Content().addMediaType("application/json",new MediaType().schema(ref(name))));
                if(Set.of("/api/health","/api/auth/login","/api/auth/register","/api/auth/departments").contains(path)) op.setSecurity(List.of());
                for(String status:List.of("400","401","403","404","409","429","503")) op.getResponses().addApiResponse(status,new ApiResponse().description("错误码及 traceId，详情参见后端接口说明").content(new Content().addMediaType("application/json",new MediaType().schema(ref("Error")))));
            }));
        };
    }
}
