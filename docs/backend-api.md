# 后端接口说明

运行服务的 `/api/openapi` 是完整请求模式与路径契约，`/api/docs` 为 Swagger UI。以下均省略 `/api` 前缀，认证请求使用 `Authorization: Bearer <登录 token>`。请求与响应 UTF-8 JSON，上传 multipart，流为 SSE，导出 CSV。

## 注册与登录

```json
// POST /auth/register：不接受 role、status 或 companyId。
{"account":"employee01","password":"至少12字符的独立密码","phone":"13800000000","name":"张三","departmentId":"product"}
// POST /auth/login
{"account":"employee01","password":"至少12字符的独立密码"}
// POST /auth/password：成功后重新登录。
{"oldPassword":"原密码","newPassword":"至少12字符的新密码"}
```

注册返回员工 ID、待确认状态、归属审核 ID、`phoneVerified:false`，不模拟短信验证。`GET /auth/departments` 公开注册选项；`GET /auth/me` 查看当前身份，`POST /auth/logout` 撤销当前会话。

## 组织与审核

| 方法和路径 | 请求/用途 |
| --- | --- |
| GET /organization | 当前范围的部门、团队及人员 |
| GET /organization/people | search、dispatch、cursor、limit；派发选择器只返回可派发在职人员 |
| POST /organization/users/{id}/revisions | version、reason，加 name、departmentId、teamId、managerId、role、status、dispatchEnabled、companyReviewer 的待改字段 |
| POST /organization/{kind}/revisions | kind 为 departments/teams；name、version、reason，既有记录带 id，团队带 departmentId |
| POST /organization/reviewer-application | 本人申请公司复核职责：version、reason |
| POST /organization/membership-application | 归属申请被驳回后，待确认员工以 version、departmentId、reason 修订重提 |
| GET /organization/review-policy | 管理员读取策略及版本 |
| POST /organization/review-policy/revisions | version、reason、taskTeamReview、taskDepartmentReview；不能关闭公司独立复核 |
| GET /organization/audit | 管理员分页查看审计 |
| GET /reviews | 本人申请及分配给本人的审核 |
| GET /reviews/{id} | 生效前值、candidate、steps、status |
| POST /reviews/{id}/decision | approve 布尔值，驳回必须附 reason |
| POST /reviews/{id}/reroute | 申请人重路由尚无已决步骤的待审申请 |

公司独立复核人缺失时候选保持待审。申请人不能自审；顺序错误或权限撤销返回 403，最终版本过期返回 409。驳回后从原业务修订接口提交新申请。

## 导图、个人面板、备注

`GET /dashboard` 返回 companyItems、companyTasks、personalItems、logs 和 canDispatch。公司重点与范围内任务在首页只读。`GET /dashboard/company` 分页查看公司重点；`POST /dashboard/company/revisions` 是独立发布入口，带 version、reason、title、text、pinned、archived、position，修改带 id。

`GET /dashboard/personal?ownerId=<范围内用户>` 查看个人重点；本人 `POST /dashboard/personal` 新建或替换记录，字段 id（新建省略）、version、title、text、pinned、archived、position。最多十条置顶且未归档重点。

`GET /profiles/{id}` 返回范围内公开面板身份、profile 和 viewingSelf；`PUT /profiles/me` 修改 avatarAttachmentId、introduction，必须带 version，不接受角色或组织字段。关联头像由同范围面板查看者授权下载。

`GET /private-notes` 仅返回本人；`PUT /private-notes` 带 resource（tasks/dashboard/company）、objectId、text、version。公共详情响应无私人备注，AI 输入不含备注。

## 任务

`POST /tasks` 必须带 `Idempotency-Key`（1–128 字符）：

```json
{"title":"准备产品评审","ownerId":"负责人ID","deadline":"2026-10-09T18:00:00+08:00","urgency":"NORMAL","group":"产品","content":"准备方案和风险清单","progressNote":"等待材料","collaborators":["协作人ID"],"attachments":["附件ID"]}
```

urgency 为 URGENT/NORMAL/LOW；主负责人仅一名。相同键同内容返回原任务，异内容返回 409 `IDEMPOTENCY_CONFLICT`。该键按派发者隔离。无管理角色或派发开关被撤销返回 403，范围外负责人拒绝。

`GET /tasks` 支持 cursor、limit、search、ownerId、date、period；列表不提供 phase、完成情况或替代状态字段。`GET /tasks/{id}` 附事件时间线。`POST /tasks/{id}/events`：

```json
{"type":"FEEDBACK","text":"提交成果及说明","version":2}
```

事件为 RECEIVED（主负责人接收）、FEEDBACK（参与者反馈）、ACCEPTED（派发者验收）、ARCHIVED（验收后归档）、WITHDRAWN（派发者撤回，理由必填）。按合法顺序执行并检查版本。

`POST /tasks/{id}/revisions` 带 `{version,reason,candidate:<完整任务字段>}`，用于期限、负责人、关键内容调整。旧内容持续生效，独立审核通过后记录 REVISED 事件、更新接收人并通知，再由新负责人接收。附件原所属任务不可随意改挂另一任务。

## 日报与日周月

`PUT /logs/draft` 保存本人草稿：

```json
{"businessDate":"2026-10-08","version":0,"body":{"work":"今日工作","blockers":"阻碍","tomorrow":"明日计划","hours":6.5,"taskIds":["任务ID"]}}
```

每人每天唯一；创建用 0，自动保存需携带服务端返回的当前版本，冲突时保留本地输入并提示刷新。允许空工作草稿；提交必须有 work 且关联任务均在当前范围。

| 方法和路径 | 用途 |
| --- | --- |
| GET /logs | 本人及管理范围已提交日志，分页/ownerId/date/period |
| GET /logs/subordinates | 管理者下属入口，仅已提交且不含本人 |
| GET /logs/{id} | 日报详情；上级不能读取草稿 |
| POST /logs/{id}/submit | `{version}`，生成提交历史、审计和待阅通知 |
| POST /logs/{id}/revisions | `{version,reason,body}`，提交修订候选 |
| GET /logs/{id}/versions | 已提交的历史版本 |
| POST /logs/{id}/read | 单独记录已读，不改日报正文 |
| GET/POST /logs/{id}/comments | GET 评语，POST `{text}`；评语独立保存 |
| GET /timeline | date、period（day/week/month）、可选 ownerId，统一范围返回日志和任务 |

period 周范围以周一为首日，结束不包含；日报使用上海业务日期，任务时间过滤转换为 UTC。列表超过 100 条继续分页，timeline 的内嵌列表也携带 total 和 nextCursor。

## 消息、分析、附件

`GET /notifications` 支持 type 和分页，含本人 unread；`POST /notifications/{id}/read`、`POST /notifications/read-all` 更新已读。`GET /notifications/stream` 需 Bearer 头，可带 `Last-Event-ID` 序号，收到 `event:notification` 后按序号去重并刷新列表。浏览器原生 EventSource 不能设置 Bearer 头，可用 fetch 读取流。

`GET /analytics?date=2026-10-08&period=week` 返回区间、更新时间、派发数、逾期数、按期验收和日报提交的分子/分母/口径、待阅数及部门分布。`GET /analytics/export` 同样 date、period，resource 为 logs/tasks，返回 UTF-8 CSV。相同权限范围再次在服务端校验。

`POST /attachments` 以 multipart `file` 上传，返回 id/filename/size；`GET /attachments/{id}` 授权下载二进制。附件可先上传再在派发中引用，未关联附件只有上传者可见，公开头像例外须符合面板范围。

## AI 与地图

| 方法和路径 | 用途 |
| --- | --- |
| POST /ai/jobs | `{date,period,purpose?,focusSourceId?}`，返回异步 job，未配置供应商返回 503 |
| GET /ai/jobs/{id} | QUEUED/RUNNING/SUCCEEDED/FAILED/CANCELLED、脱敏 input、output、tokens、version |
| GET /ai/jobs/{id}/stream | delta 为累计草稿 text，result 为终态 job |
| DELETE /ai/jobs/{id} | 取消排队或进行中的供应商请求 |
| POST /ai/jobs/{id}/retry | 从失败/取消 job 重建当前授权输入，返回新 job |
| PUT /ai/jobs/{id}/draft | version、summary、sourceIds、nodes、actions；保留原生成时间，校验来源和建议负责人 |
| POST /ai/jobs/{id}/confirm-task | `{actionIndex,task:<人工确认完整任务>}`，必须带 Idempotency-Key，走普通派发鉴权 |
| GET /ai/usage | 本人每日 tokens/jobs 和日限额 |
| GET /ai-maps | 本人仍有权限读取来源的 nodes/edges |
| POST /ai-maps/edges | sourceId、targetId、label，节点必须归本人且来源有效 |

输出为 `{summary,sourceIds,nodes,actions,generatedAt,draft:true}`。node 包含 title、type（GOAL/RESULT/BLOCKER/RISK）、sourceIds；action 包含 title、可选 ownerId、sourceIds。来源 ID 为 log:/task:/item: 前缀，来源 URL 保存在 input.sources。最多十个节点、三个优先行动。确认只是明确触发正规 API；模型生成、人工改稿或绘制边不会自动派发。

purpose 默认 SUMMARY（区间总结），可选 EXPLAIN_RISK（解释风险）、SPLIT_STEPS（拆分步骤）、DRAFT_TASK（起草任务）。后三种须提供 focusSourceId，选择当前范围内日志、任务或个人重点的来源 ID；失权来源拒绝。

## 常见错误

| HTTP | code 举例 | 客户端处理 |
| --- | --- | --- |
| 400 | INVALID_FIELD / UNKNOWN_FIELD / INVALID_REQUEST | 修正字段、日期或缺失头 |
| 401 | UNAUTHENTICATED / SESSION_EXPIRED / INVALID_CREDENTIALS | 登录或重新登录 |
| 403 | MEMBERSHIP_PENDING / PASSWORD_CHANGE_REQUIRED / FORBIDDEN / SELF_REVIEW | 显示对应入口，不能改对象 ID 绕过 |
| 404 | NOT_FOUND | 记录不存在或当前无可见范围 |
| 409 | VERSION_CONFLICT / DATA_CONFLICT / REVIEW_REQUIRED / IDEMPOTENCY_CONFLICT | 保留输入，刷新版本或进入修订审批 |
| 413 | FILE_TOO_LARGE | 缩小附件 |
| 429 | RATE_LIMITED | 等待后重试 |
| 503 | AI_NOT_CONFIGURED / LIMITER_UNAVAILABLE | 提示功能暂时不可用 |

AI 供应商失败、预算不足与超时通常保存在已创建 job 的 FAILED 状态和 error 字段，基础工作接口独立可用。
