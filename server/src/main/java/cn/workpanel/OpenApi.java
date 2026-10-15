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
        for(String field:List.of("group","content","progressNote")) task.addProperty(field,text()); task.addProperty("collaborators",ids().description("去重排序后参与幂等摘要；与主负责人重复时忽略")); task.addProperty("attachments",ids().description("仅本人上传且未关联任务的附件，已关联其他任务返回 ATTACHMENT_BOUND")); task.setDescription("派发内容。phase、version、status、completion 等服务端字段不可提交（SERVER_MANAGED_FIELD）"); c.addSchemas("TaskDraft",task);
        var taskListItem=object("id","owner_id","issuer_id","title","deadline","version","created_at"); taskListItem.addProperty("id",text()); taskListItem.addProperty("owner_id",text()); taskListItem.addProperty("issuer_id",text()); taskListItem.addProperty("title",text()); taskListItem.addProperty("deadline",new DateTimeSchema()); taskListItem.addProperty("version",version()); taskListItem.addProperty("created_at",new DateTimeSchema()); taskListItem.setDescription("任务列表安全投影；不返回 phase、status、completion、progress、正文、事件或任何替代状态字段。"); c.addSchemas("TaskListItem",taskListItem);
        c.addSchemas("TaskRevision",revision("TaskDraft","candidate"));
        var event=object("type","version"); event.addProperty("type",new StringSchema()._enum(List.of("RECEIVED","FEEDBACK","ACCEPTED","RETURNED","ARCHIVED","WITHDRAWN"))); event.addProperty("version",version()); event.addProperty("text",text().maxLength(2000).description("反馈、退回、撤回必填（1–2000 字）")); c.addSchemas("TaskEvent",event);
        var reassignment=object("ownerId","version","reason"); reassignment.addProperty("ownerId",text().minLength(1)); reassignment.addProperty("version",version()); reassignment.addProperty("reason",text().minLength(1)); c.addSchemas("TaskReassignment",reassignment);
        var reschedule=object("deadline","version","reason"); reschedule.addProperty("deadline",new DateTimeSchema().description("带时区的 ISO-8601 时间，且不得与当前截止时间相同")); reschedule.addProperty("version",version()); reschedule.addProperty("reason",text().minLength(1)); c.addSchemas("TaskReschedule",reschedule);
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
        var development=object("domain"); development.addProperty("domain",new StringSchema()._enum(List.of("PERSONAL","ORGANIZATION"))); development.addProperty("scopeType",new StringSchema()._enum(List.of("SELF","TEAM","DEPARTMENT","COMPANY")));development.addProperty("scopeId",text());c.addSchemas("DevelopmentRequest",development);
        var memory=object("content");memory.setProperties(new LinkedHashMap<>(development.getProperties()));memory.addProperty("content",text().minLength(1).maxLength(4000));memory.addProperty("category",new StringSchema()._enum(List.of("EXPERIENCE","OUTCOME","GOAL","PREFERENCE","LESSON","SKILL")));memory.addProperty("claimType",new StringSchema()._enum(List.of("FACT","OBSERVATION","HYPOTHESIS")));memory.addProperty("reason",text());c.addSchemas("MemoryCreate",memory);
        var memoryContent=object("content");memoryContent.addProperty("content",text().minLength(1).maxLength(4000));c.addSchemas("MemoryContent",memoryContent);c.addSchemas("MemoryRevision",revision("MemoryContent","candidate"));
        var memoryConfirm=object("version");memoryConfirm.addProperty("version",version());memoryConfirm.addProperty("reason",text());c.addSchemas("MemoryConfirm",memoryConfirm);
        var preferences=object("version");preferences.addProperty("version",version());preferences.addProperty("explicitGoals",text().maxLength(2000));preferences.addProperty("responsePreferences",text().maxLength(2000));c.addSchemas("MemoryPreferences",preferences);
        var feedback=object("itemKey","type");feedback.addProperty("itemKey",text());feedback.addProperty("type",new StringSchema()._enum(List.of("HELPFUL","UNHELPFUL","DIRECTION_MISMATCH","TOO_DIFFICULT")));feedback.addProperty("comment",text());c.addSchemas("DevelopmentFeedback",feedback);
        var scope=object("domain","scopeType","scopeId","label");for(String field:List.of("domain","scopeType","scopeId","label")) scope.addProperty(field,text());c.addSchemas("DevelopmentScope",scope);
        var source=object("id","memoryId","memoryVersion","chunkId","locator","text");
        for(String field:List.of("id","memoryId","chunkId","locator","text","claimType","provenance","url")) source.addProperty(field,text());
        source.addProperty("memoryVersion",version());source.addProperty("version",version());c.addSchemas("DevelopmentEvidence",source);
        var output=object("analysisId","domain","summary","basisQuality","sources");
        for(String field:List.of("analysisId","domain","summary","basisQuality","memoryRevision","generatedAt")) output.addProperty(field,text());
        output.addProperty("sources",new ArraySchema().items(ref("DevelopmentEvidence")));output.addProperty("facts",new ArraySchema().items(new ObjectSchema()));
        output.addProperty("paths",new ArraySchema().items(new ObjectSchema()));output.addProperty("directions",new ArraySchema().items(new ObjectSchema()));
        output.addProperty("suggestions",new ArraySchema().items(new ObjectSchema()));output.addProperty("gaps",new ArraySchema().items(text()));
        output.addProperty("basisReasons",new ArraySchema().items(text()));output.addProperty("retrieval",new ObjectSchema());c.addSchemas("DevelopmentOutput",output);
        var analysis=object("id","domain","scope_type","scope_id","state");
        for(String field:List.of("id","domain","scope_type","scope_id","error","created_at","finished_at")) analysis.addProperty(field,text());
        analysis.addProperty("state",new StringSchema()._enum(List.of("QUEUED","RUNNING","SUCCEEDED","FAILED","CANCELLED","STALE")));
        analysis.addProperty("tokens",version());analysis.addProperty("output",ref("DevelopmentOutput"));c.addSchemas("DevelopmentJob",analysis);
        var latest=object("scopes","analysis");latest.addProperty("scopes",new ArraySchema().items(ref("DevelopmentScope")));
        latest.addProperty("analysis",new ComposedSchema().addOneOfItem(ref("DevelopmentJob")).addOneOfItem(object()));c.addSchemas("DevelopmentLatest",latest);
        var evidencePage=object("items","total");evidencePage.addProperty("items",new ArraySchema().items(ref("DevelopmentEvidence")));evidencePage.addProperty("total",version());c.addSchemas("DevelopmentEvidencePage",evidencePage);
        var memoryItem=object("id","status","version","content");
        for(String field:List.of("id","company_id","domain","owner_id","scope_type","scope_id","category","claim_type","status","content","source_type","source_id","locator","provenance")) memoryItem.addProperty(field,text());
        memoryItem.addProperty("version",version());memoryItem.addProperty("source_version",version());c.addSchemas("MemoryItem",memoryItem);
        var reviewSubmission=object("id","status","target_id");for(String field:List.of("id","status","target_id")) reviewSubmission.addProperty(field,text());c.addSchemas("MemoryReviewSubmission",reviewSubmission);
        c.addSchemas("MemoryMutation",new ComposedSchema().addOneOfItem(ref("MemoryItem")).addOneOfItem(ref("MemoryReviewSubmission")));
        var memoryPage=object("items","total","nextCursor");memoryPage.addProperty("items",new ArraySchema().items(ref("MemoryItem")));memoryPage.addProperty("total",version());memoryPage.addProperty("nextCursor",version());c.addSchemas("MemoryPage",memoryPage);
        var preferencesResult=object("version","explicit_goals","response_preferences");preferencesResult.addProperty("version",version());preferencesResult.addProperty("explicit_goals",text());preferencesResult.addProperty("response_preferences",text());c.addSchemas("MemoryPreferencesResult",preferencesResult);
        var backfill=object("processed","nextCursor","done");backfill.addProperty("processed",version());backfill.addProperty("nextCursor",version());backfill.addProperty("done",new BooleanSchema());c.addSchemas("MemoryBackfill",backfill);
        var feedbackResult=object("ok","message");feedbackResult.addProperty("ok",new BooleanSchema());feedbackResult.addProperty("message",text());c.addSchemas("DevelopmentFeedbackResult",feedbackResult);
        var cancelled=object("state");cancelled.addProperty("state",new StringSchema()._enum(List.of("CANCELLED")));c.addSchemas("DevelopmentCancelled",cancelled);
        var knowledge=object("memories","indexedMemories","indexingMemories","candidates");for(String field:List.of("memories","indexedMemories","indexingMemories","candidates")) knowledge.addProperty(field,version());c.addSchemas("KnowledgeStatus",knowledge);
        var indexJob=object("id","type","state","target_version","cursor_id","processed");
        for(String field:List.of("id","target_version","cursor_id","error")) indexJob.addProperty(field,text());
        indexJob.addProperty("type",new StringSchema()._enum(List.of("KNOWLEDGE_INDEX")));
        indexJob.addProperty("state",new StringSchema()._enum(List.of("BUILDING","SUCCEEDED","FAILED")));
        indexJob.addProperty("processed",version());
        var failedIndex=object("id","memory_id","error");for(String field:List.of("id","memory_id","error")) failedIndex.addProperty(field,text());
        indexJob.addProperty("failedJobs",new ArraySchema().items(failedIndex));c.addSchemas("KnowledgeIndexRebuild",indexJob);
        var indexRetry=object("id","type","state");indexRetry.addProperty("id",text());indexRetry.addProperty("type",new StringSchema()._enum(List.of("KNOWLEDGE_INDEX")));indexRetry.addProperty("state",new StringSchema()._enum(List.of("QUEUED")));c.addSchemas("KnowledgeIndexRetry",indexRetry);
        var forgetJob=object("id","state");forgetJob.addProperty("id",text());forgetJob.addProperty("state",new StringSchema()._enum(List.of("PENDING","SUCCEEDED","FAILED")));forgetJob.addProperty("error",text());forgetJob.addProperty("message",text());c.addSchemas("MemoryForgetJob",forgetJob);
        var error=object("code","message","traceId"); for(String field:List.of("code","message","traceId")) error.addProperty(field,text()); c.addSchemas("Error",error);
        return new OpenAPI().servers(List.of(new io.swagger.v3.oas.models.servers.Server().url("/"))).info(new Info().title("企业协作智能面板 API").version("1.0.0").description("UTC 时间，Asia/Shanghai 业务日期，周一为周首。重要修改提交候选审核；任务列表不提供完成情况。分页 cursor 是非负偏移量。" )).components(c).addSecurityItem(new SecurityRequirement().addList("bearer"));
    }
    @Bean OpenApiCustomizer requestModels() {
        return api->{
            var bodies=Map.ofEntries(
                Map.entry("POST /api/auth/register","Registration"),Map.entry("POST /api/auth/login","Login"),Map.entry("POST /api/auth/password","PasswordChange"),
                Map.entry("POST /api/tasks","TaskDraft"),Map.entry("POST /api/tasks/{id}/events","TaskEvent"),Map.entry("POST /api/tasks/{id}/reassignments","TaskReassignment"),Map.entry("POST /api/tasks/{id}/reschedules","TaskReschedule"),Map.entry("POST /api/tasks/{id}/revisions","TaskRevision"),
                Map.entry("PUT /api/logs/draft","LogDraft"),Map.entry("POST /api/logs/{id}/submit","Version"),Map.entry("POST /api/logs/{id}/revisions","LogRevision"),Map.entry("POST /api/logs/{id}/comments","Comment"),
                Map.entry("POST /api/reviews/{id}/decision","ReviewDecision"),Map.entry("POST /api/organization/membership-application","MembershipApplication"),Map.entry("POST /api/organization/reviewer-application","ReviewerApplication"),Map.entry("POST /api/organization/review-policy/revisions","ReviewPolicy"),Map.entry("POST /api/organization/users/{id}/revisions","UserRevision"),Map.entry("POST /api/organization/{kind}/revisions","UnitRevision"),
                Map.entry("POST /api/dashboard/company/revisions","CompanyItemRevision"),Map.entry("POST /api/dashboard/personal","PersonalItem"),Map.entry("PUT /api/private-notes","PrivateNote"),Map.entry("PUT /api/profiles/me","Profile"),
                Map.entry("POST /api/ai/jobs","AiJobRequest"),Map.entry("PUT /api/ai/jobs/{id}/draft","AiDraftEdit"),Map.entry("POST /api/ai/jobs/{id}/confirm-task","ConfirmTask"),Map.entry("POST /api/ai-maps/edges","MapEdge"),
                Map.entry("POST /api/ai-maps/development/jobs","DevelopmentRequest"),Map.entry("POST /api/ai-memories","MemoryCreate"),Map.entry("POST /api/ai-memories/{id}/revisions","MemoryRevision"),Map.entry("POST /api/ai-memories/{id}/confirm","MemoryConfirm"),Map.entry("PUT /api/ai-memories/preferences/me","MemoryPreferences"),Map.entry("POST /api/ai-maps/development/{id}/feedback","DevelopmentFeedback"));
            var responses=Map.ofEntries(
                Map.entry("GET /api/ai-maps/development","DevelopmentLatest"),Map.entry("POST /api/ai-maps/development/jobs","DevelopmentJob"),
                Map.entry("GET /api/ai-maps/development/jobs/{id}","DevelopmentJob"),Map.entry("POST /api/ai-maps/development/jobs/{id}/retry","DevelopmentJob"),
                Map.entry("DELETE /api/ai-maps/development/jobs/{id}","DevelopmentCancelled"),Map.entry("POST /api/ai-maps/development/{id}/feedback","DevelopmentFeedbackResult"),
                Map.entry("GET /api/ai-maps/development/{id}/evidence","DevelopmentEvidencePage"),
                Map.entry("GET /api/ai-memories","MemoryPage"),Map.entry("POST /api/ai-memories","MemoryMutation"),
                Map.entry("POST /api/ai-memories/{id}/revisions","MemoryMutation"),Map.entry("POST /api/ai-memories/{id}/confirm","MemoryMutation"),
                Map.entry("GET /api/ai-memories/preferences/me","MemoryPreferencesResult"),Map.entry("PUT /api/ai-memories/preferences/me","MemoryPreferencesResult"),
                Map.entry("POST /api/ai-memories/backfill","MemoryBackfill"),Map.entry("GET /api/ai-memories/knowledge-status","KnowledgeStatus"),
                Map.entry("POST /api/ai-memories/index-rebuild","KnowledgeIndexRebuild"),Map.entry("GET /api/ai-memories/index-rebuild/{id}","KnowledgeIndexRebuild"),
                Map.entry("POST /api/ai-memories/index-jobs/{id}/retry","KnowledgeIndexRetry"),
                Map.entry("DELETE /api/ai-memories/{id}","MemoryForgetJob"),Map.entry("GET /api/ai-memories/forget-jobs/{id}","MemoryForgetJob"));
            var dispatch=api.getPaths().get("/api/tasks"); if(dispatch!=null&&dispatch.getPost()!=null) {
                var op=dispatch.getPost(); op.setDescription("派发任务。同一派发人同一 Idempotency-Key 重放相同内容返回同一任务，内容不同返回 409 IDEMPOTENCY_CONFLICT；附件已关联其他任务返回 409 ATTACHMENT_BOUND；服务端字段返回 400 SERVER_MANAGED_FIELD。");
                if(op.getParameters()!=null) op.getParameters().stream().filter(p->"Idempotency-Key".equals(p.getName())).forEach(p->{ p.setRequired(true); p.setSchema(new StringSchema().minLength(1).maxLength(128)); p.setDescription("1–128 位，按派发人隔离"); });
            }
            if(dispatch!=null&&dispatch.getGet()!=null) dispatch.getGet().setDescription("在服务端组织数据范围内分页查询任务。列表项仅为 TaskListItem，永不返回阶段、完成情况、进度、正文或事件；ownerId 越权返回 403，其他公司 ownerId 返回 404。");
            var taskEvents=api.getPaths().get("/api/tasks/{id}/events"); if(taskEvents!=null&&taskEvents.getPost()!=null) taskEvents.getPost().setDescription("生命周期动作。非法状态转换返回 409 INVALID_TRANSITION；旧版本返回 409 VERSION_CONFLICT；未知动作返回 400 INVALID_EVENT。反馈、退回、撤回必须提供 text。");
            var reassignment=api.getPaths().get("/api/tasks/{id}/reassignments"); if(reassignment!=null&&reassignment.getPost()!=null) reassignment.getPost().setDescription("提交转派复核申请；申请不会立即更换负责人。新旧负责人相同返回 400 SAME_OWNER，终态返回 409 INVALID_TRANSITION。");
            var reschedule=api.getPaths().get("/api/tasks/{id}/reschedules"); if(reschedule!=null&&reschedule.getPost()!=null) reschedule.getPost().setDescription("提交改期复核申请；申请不会立即改期。必须提供带时区、不同于当前值的 deadline。");
            var logDraft=api.getPaths().get("/api/logs/draft"); if(logDraft!=null&&logDraft.getPut()!=null) logDraft.getPut().setDescription("保存本人每日唯一日报草稿。草稿仅本人可读；version 过期返回 409，已提交日报须走候选修订。");
            var logSubmit=api.getPaths().get("/api/logs/{id}/submit"); if(logSubmit!=null&&logSubmit.getPost()!=null) logSubmit.getPost().setDescription("仅日报本人可按当前 version 提交。提交会记录时间和历史版本；重复或旧版本提交返回 409。");
            var logRevision=api.getPaths().get("/api/logs/{id}/revisions"); if(logRevision!=null&&logRevision.getPost()!=null) logRevision.getPost().setDescription("已提交日报的候选修订。草稿返回 400 DRAFT_LOG；审核通过时发生版本冲突将拒绝覆盖。");
            var logs=api.getPaths().get("/api/logs"); if(logs!=null&&logs.getGet()!=null) logs.getGet().setDescription("分页查询本人草稿或组织范围内已提交日报。ownerId 其他公司返回 404，同公司范围外返回 403；非本人草稿永不返回。");
            var subordinates=api.getPaths().get("/api/logs/subordinates"); if(subordinates!=null&&subordinates.getGet()!=null) subordinates.getGet().setDescription("下属日报固定入口。仅管理者可用，只返回组织范围内他人的已提交日报；草稿永不出现。");
            api.getPaths().forEach((path,item)->item.readOperationsMap().forEach((method,op)->{
                String name=bodies.get(method.name()+" "+path); if(name!=null&&op.getRequestBody()!=null) op.getRequestBody().setContent(new Content().addMediaType("application/json",new MediaType().schema(ref(name))));
                String response=responses.get(method.name()+" "+path);
                if(response!=null) {
                    String status=Set.of("POST /api/ai-maps/development/jobs","POST /api/ai-maps/development/jobs/{id}/retry","DELETE /api/ai-memories/{id}","POST /api/ai-memories/index-rebuild","POST /api/ai-memories/index-jobs/{id}/retry").contains(method.name()+" "+path)?"202":"200";
                    op.getResponses().addApiResponse(status,new ApiResponse().description("当前授权结果").content(new Content().addMediaType("application/json",new MediaType().schema(ref(response)))));
                }
                if(Set.of("/api/health","/api/auth/login","/api/auth/register","/api/auth/departments").contains(path)) op.setSecurity(List.of());
                for(String status:List.of("400","401","403","404","409","429","503")) op.getResponses().addApiResponse(status,new ApiResponse().description("错误码及 traceId，详情参见后端接口说明").content(new Content().addMediaType("application/json",new MediaType().schema(ref("Error")))));
            }));
        };
    }
}
