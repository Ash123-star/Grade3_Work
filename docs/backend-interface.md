# 后端接口文档

## 契约来源与通用约定

实现事实以 SpringDoc 运行时文档 `GET /api/openapi` 为准；提交到仓库的 `docs/openapi.json` 是同一份契约快照，本文件只解释调用规则。三者必须同步更新，客户端不得根据旧版本猜测字段。

2026-10-29 本批状态：六组 P0 及 #17 的代码/运行时 schema 正在接入，尚未测试、编译、启动服务或执行迁移。`docs/openapi.json` 仍为旧运行时快照，须在最终统一验收时重新生成；以下新增契约不是运行成功证明。

根路径为 `/api`。除公开登录、注册和健康检查外均需 `Authorization: Bearer <session-token>`。每个响应带 `X-Trace-Id`；错误体为 `{code,message,traceId}`。列表使用 `{items,total,nextCursor}`，`cursor` 为偏移量，`limit` 范围 1–100。时间使用 UTC ISO-8601，业务日期按 `Asia/Shanghai` 且周一为周首。

移动端补充协议见 [`mobile-openapi-contract.yaml`](mobile-openapi-contract.yaml)，并由 `docs/openapi.json` 的 `x-mobile-contract` 标记引用。对该覆盖文件列出的 path、operation 和 schema，以覆盖文件为目标契约；当前状态为 `IMPLEMENTED_UNVERIFIED`，对应源码已接入但尚未通过编译、数据库升级和 HTTP 验收。最终统一验收时必须同步 SpringDoc、`docs/openapi.json` 和移动端 HTTP contract tests。逐项源码接入与验收待办见 [`mobile-p0-implementation-status.md`](mobile-p0-implementation-status.md)。

移动端与服务端的逐项缺口、当前实现状态和后端接手验收要求见 [`mobile/docs/backend-contract-gaps-mobile-page-experience-refresh.md`](../mobile/docs/backend-contract-gaps-mobile-page-experience-refresh.md)。其中“缺失/不匹配”只表示协议或运行端点尚未兑现，不表示移动端 Mock 已替代服务端业务。

写请求只接受文档列出的字段。更新请求携带 `version`；创建请求可携带 `Idempotency-Key`。版本冲突返回 `409`，越权对象通常返回 `404`，明确的人员筛选越权返回 `403`。

## 认证 `/auth`

| 方法 | 路径 | 用途与权限 | 请求 | 返回/错误 |
| --- | --- | --- | --- | --- |
| GET | `/auth/departments` | 注册前读取公司部门；公开 | 无 | 部门数组；服务不可用 |
| POST | `/auth/register` | 创建待确认员工；公开；禁止 role 字段 | `account,password,phone,name,departmentId` | 员工和 membership review；400 字段/密码/手机号错误，409 重复 |
| POST | `/auth/login` | 创建会话；公开 | `account,password` | token、过期时间和用户；401 凭据错误，429 限流 |
| GET | `/auth/me` | 当前用户；已登录 | 无 | 用户公开资料；401 会话失效 |
| POST | `/auth/password` | 首次或主动改密；本人 | `oldPassword,newPassword` | `reloginRequired`；401 原密码错误，400 密码策略 |
| POST | `/auth/logout` | 撤销当前会话；本人 | 无 | `{ok:true}`；401 会话失效 |

## 组织 `/organization`

2026-10-30（Issue #49，源码实现，未运行验收）：`GET /organization/people` 每项新增 `participatingTaskCount`、`activeTaskCount`、`todayLogStatus`、`summaryDate`。任务计数同时限制在当前请求人任务权限和该成员参与关系内，未结束任务排除 ACCEPTED/ARCHIVED/WITHDRAWN；日志状态为 SUBMITTED/MISSING/UNKNOWN，以服务端上海业务日及已提交记录计算，待确认账号 UNKNOWN，不返回他人草稿信息。前端字段缺失显示未知，不伪造0或缺交。

任务事件 `actor_name`、审核步骤 `reviewer_name`、审计 `actor_name` 为同公司 `users.name`。姓名缺失显示未知成员，不回退登录账号/内部ID。日志保留业务日期，但列表/卡片标题从work首个非空行生成最多48字符摘要，无正文显示工作日志，无新增存储字段。运行时OpenAPI模式已同步；`docs/openapi.json`快照留待统一验收时重新导出。

组织树和 `/people` 返回范围内数据。管理员策略、人员和组织单元的关键变更使用 `version`、`reason`，通过审核后生效。主要接口：`GET /organization`、`GET /organization/departments`、`GET /organization/people`、`POST /organization/membership-application`、`GET/POST /organization/review-policy`、`POST /organization/reviewer-application`、`POST /organization/users/{id}/revisions`、`POST /organization/{departments|teams}/revisions`、`GET /organization/audit`。

## 任务 `/tasks`

2026-10-30（Issue #49）：`GET /tasks/received-card` 仅返回当前用户本人参与的任务（包括本人派发且参与），包含全部生命周期状态，不再返回仅下属参与的授权范围任务。`items/total/nextCursor`使用相同过滤；每项增加`issuer_id`。导图卡片与完整列表共用该资源，管理任务表继续使用`GET /tasks`授权范围查询。

`GET /tasks` 列表故意不返回完成情况或状态列，也不返回主负责人或协作人；每项只返回无角色的 `participants` 集合和最多一个由服务端给出的 `label`。流转事件只在 `GET /tasks/{id}` 的 `events` 中返回。`POST /tasks` 提交创建审核，需 `title,participants,deadline`、可选 `startAt,labelId,attachments,acceptanceChecklist` 和 `Idempotency-Key`；审核批准后才产生正式任务，同键重放返回同一审核申请。

`GET /tasks?date=YYYY-MM-DD&period=day|week|month` 使用上海自然日/周/月按任务区间相交筛选：`COALESCE(start_at,deadline) < 范围结束 && deadline >= 范围开始`，排除反向区间。移动端自行计算月历可见网格并发送成对带时区的 `from/to`；不得与 `date/period` 混用。`participantId` 为正式参与人参数，`ownerId` 是兼容别名，同时出现且不同返回400。

移动端新月历调用的正式目标形状为 `GET /tasks?from=<inclusive-ISO8601>&to=<exclusive-ISO8601>&ownerId=<optional-id>`；导图接收卡片使用 `GET /tasks/received-card?cursor&limit&search`，返回 `id/title/version/dispatchAt/phase` 和卡片所需的参与人、标签字段。`phase` 必须区分 `DISPATCHED/RECEIVED/FEEDBACK/ACCEPTED/ARCHIVED/WITHDRAWN`，服务端不得让客户端从缺失字段推导完成状态。

`POST /tasks/{id}/events` 请求至少包含当前 `version` 和 `type`。事件枚举及附加字段如下：

| type | 权限 | 必填附加字段 | 结果 |
| --- | --- | --- | --- |
| `RECEIVED` | 负责人 | 无 | 任务进入已接收 |
| `FEEDBACK` | 负责人/协作人 | `text` | 追加反馈 |
| `ACCEPTED` | 派发人/管理员 | 无 | 任务验收 |
| `TRANSFERRED` | 派发人/管理员 | `ownerId` | 更换负责人并重建主负责人关联 |
| `RESCHEDULED` | 派发人/管理员 | `deadline` | 更新截止时间，必须晚于当前时间 |
| `ARCHIVED` | 派发人/管理员 | 无 | 归档已验收任务 |
| `WITHDRAWN` | 派发人/管理员 | `text` | 撤回未验收任务 |

事件更新使用乐观锁；版本不匹配返回 `409 VERSION_CONFLICT`，字段缺失或时间格式错误返回 `400`。事件写入和任务更新在同一事务中完成。

`POST /tasks/{id}/revisions` 修改已发布任务并携带版本、理由和候选内容，批准后才生效；候选可调整参与人、唯一标签、开始/截止时间和说明。`POST /tasks/{id}/deletions` 带 `{version,reason}` 提交删除审核，批准后归档而非物理删除。两个操作均拒绝旧版本覆盖。

转派/改期继续走专用复核申请；`REASSIGNED`/`RESCHEDULED` 只在审核生效后写入时间线，不能通过事件接口直接写入。

`GET/POST /tasks/{taskId}/comments` 读取或新增任务公开评论。评论包含作者、昵称、头像标识、时间、正文与可选 `parentId`；有任务读取权限者可读，派发人、参与人或管理员可写。新增必须给 `Idempotency-Key`，评论不可编辑或删除，评论、审计与通知 outbox 同一事务写入。标签由 `GET/POST/PUT /task-labels` 管理，直接写入仅创始人可用，更新携带 `version`。

## 日志 `/logs`

`GET /logs` 只返回本人草稿或授权范围内已提交日志；下属列表、月状态与详情共享组织范围和真实祖先关系。`PUT /logs/draft` 保存每日唯一草稿，首次提交仅允许上海今天和此前两日。已提交正文由本人在原始24小时内 `PUT /logs/{id}/content` 直改。已删除日志修订、撤回和阅读登记三条旧 HTTP 路由（请求返回404 `NOT_FOUND`），历史待审LOG候选迁移为 `SUPERSEDED`，不能延迟覆盖正文；旧历史字段和版本保留。阅读登记不再提供写入口，统计不再使用待阅指标。

移动端日期范围列表同时支持 `from/to`；成员月状态使用 `GET /logs/subordinates/calendar?ownerId=<id>&month=YYYY-MM`，返回 `employmentStartDate` 和逐日 `SUBMITTED/MISSING/FUTURE/UNKNOWN`。首次提交后的直接正文修改使用 `PUT /logs/{id}/content`，请求 `{work,version}`，只能由本人在 `submitted_at + 24h` 前执行，必须保留首次提交时间并递增版本。

## 审核 `/reviews`

`GET /reviews`、`GET /reviews/{id}` 返回申请人或当前仍有权的分配审核人可见内容，包含尚有当前权限的已决历史，SUPERSEDED步骤不提供读取权限。`POST /reviews/{id}/decision` 请求 `{approve,reason,expectedVersion}`，驳回须理由，禁止自审并复核目标版本及当前直属关系。除 `MEMBERSHIP` 管理员确认外，使用 `DIRECT_MANAGER` 单级审核；有效创始人权限内新操作自动批准并记录 `FOUNDER_EXEMPT`，管理员不免审。无审核人保持待审。`POST /reviews/{id}/reroute` 仅申请人继续PENDING申请，保留已决历史、替代待审步骤；有效创始人明确继续本人非MEMBERSHIP申请时，才按当前业务权限和目标版本免审应用，重复已免审请求返回原结果。迁移不会自动应用任何历史候选。

## 仪表盘、通知、分析和附件

仪表盘提供 `/dashboard`、`/dashboard/company`、`/dashboard/personal`、`/profiles/{id}` 和 `/private-notes`；私人备注始终仅本人可见。`PUT /profiles/me` 的移动端协议字段为 `introduction/phone/email/gender/age/avatarAttachmentId/version`，姓名、部门、职位、角色和状态只读。通知提供 `GET /notifications`、`POST /notifications/read-all`、`POST /notifications/{id}/read` 和支持 `Last-Event-ID` 的 `/notifications/stream`。分析提供 `/analytics`、`/analytics/details`、`/timeline` 和 `/analytics/export`；汇总、钻取与 CSV 必须共用 `groupBy/departmentId/teamId/ownerId`、日期窗口和权限范围。附件 `POST /attachments` 使用 multipart，单文件最大 10MB；`GET /attachments/{id}` 每次重新鉴权，不提供公开 URL。

## AI `/ai`

`POST /ai/jobs` 创建异步草稿，`GET/DELETE /ai/jobs/{id}` 查询或取消，`POST /ai/jobs/{id}/retry` 重试，`PUT /ai/jobs/{id}/draft` 按版本编辑，`GET /ai/jobs/{id}/stream` 读取 SSE，`GET /ai/usage` 查看用量。`GET /ai-maps` 和 `POST /ai-maps/edges` 管理本人范围内地图。`POST /ai/jobs/{id}/confirm-task` 必须带幂等键，确认后重新走任务派发权限和事务；AI 失败返回 job 状态，不影响普通任务和日志。

## Flutter 接口缺口（待完成）

2026-10-29剩余接口实现状态见 [mobile-remaining-api-implementation-status.md](mobile-remaining-api-implementation-status.md)。任务评论/日志回复和RETURNED后端已存在，本批接通客户端退回及通知映射；成果反馈增加最多5个attachments（仅本人上传同公司可用材料，复用任务读取授权）。`GET /organization/teams`返回当前组织树范围内团队目录。意见反馈已由用户取消，移动端入口/表单/Mock资源移除，旧深链返回帮助页；不新增feedback接口。阅读登记已停用，不新增阅读人员清单。

AI作业创建增加 `scope=SELF|AUTHORIZED`（默认AUTHORIZED），服务端权限仍是上限，SELF仅本人日志、参与/派发任务和本人重点，后台执行/重试保留范围。确认请求为 `{version,actionIndex,task}`，必须携带1–128位Idempotency-Key；作业行锁、当前来源及派发权限、版本检查、任务/审核创建和V23确认回执同事务。首次旧版本返回409 VERSION_CONFLICT，同键同规范化命令重放原结果，同键异内容409 IDEMPOTENCY_CONFLICT；重放仍重验当前及原行动来源。返回TASK_CREATE审核对象，客户端跳转审核结果，不能将申请ID当任务ID。上述源码均未编译、测试、启动或迁移；最终统一验收时重新生成运行时快照。

## 长期记忆与发展分析（2026-10-15 整合）

所有接口由服务端按当前用户、公司及个人/组织范围鉴权；来源版本、撤权与遗忘状态重新校验。具体字段和成功响应 schema 见运行时 `/api/openapi` 与 `docs/openapi.json`。

- `/api/ai-maps/development`：查询当前发展分析；`POST /api/ai-maps/development/jobs` 使用 `Idempotency-Key` 创建异步分析，返回 202；作业支持查询、重试、取消、证据和反馈。
- `/api/ai-memories`：授权记忆查询与新增；修订、确认使用版本校验，组织关键记忆走独立审核；删除创建遗忘作业，返回 202，并可查询清理状态。
- `/api/ai-memories/preferences/me`：仅本人读写目标和偏好；更新携带 version。
- `/api/ai-memories/knowledge-status`：授权知识索引状态；管理员可回填、重建索引及重试失败索引作业。
- 无 DeepSeek 配置或供应商异常返回受控错误，基础任务日报不依赖模型成功；分析内容是建议，不自动创建任务。

部署新增 V10/V11，旧实验库升级限制与验证见 `local-memory-integration.md`。

## 调用示例

```http
POST /api/tasks
Authorization: Bearer <token>
Idempotency-Key: task-20261009-001
Content-Type: application/json

{"title":"整理周报","deadline":"2026-10-10T09:00:00Z","ownerId":"user-id","body":{}}
```

```json
{"code":"VERSION_CONFLICT","message":"数据已被其他操作修改","traceId":"..."}
```

## week6 成员 B 增量（Issue #22）

- 日志首次提交时间为不可重置窗口起点：不足24小时可申请修订，恰好及超过24小时返回 `409 LOG_EDIT_WINDOW_EXPIRED`。管理员没有窗口例外；窗口内申请可窗口外完成审核，仍校验版本与独立审核。
- `POST /api/logs/{id}/withdraw`：仅本人，body `{version,reason}`。窗口内将已提交日志撤回为私有草稿，保留首次 `submitted_at`，递增版本。重复或旧版本409，非本人403，范围外404。重提沿用首次时间，撤回后的草稿超过窗口也不可写入。
- 日志列表/详情增量返回 `submittedAt`、`editableUntil`（ISO-8601 UTC或null）、`canEdit`、`canWithdraw`；字段只辅助展示，每次写请求仍服务端检查。旧 snake_case 字段保留兼容。
- `GET /api/logs/subordinates` 增加 `departmentId`、`search`，可与原 `ownerId/date/period/cursor/limit` 组合。search为最多100字的字面子串，匹配日志JSON内容、人员姓名或账号。原日志结构没有独立标题字段；不虚构标题搜索字段。部门取人员当前归属。
- 下属返回 `items/total/nextCursor` 并新增 `groups:[{department:{id,name},items:[...]}]`；groups只分组当前日志页，同一部门可能跨页。条目新增 `author:{id,name}`、`department:{id,name}`。total在权限与筛选之后计算。未知/越权部门均空结果；员工入口403；不返回他人草稿。
- 独立 `web/` 工作台非认证业务调用 `/api/admin/workspace` + 原业务路径。服务端重新读取当前身份，必须ADMIN后才委托原AI工作台及组织审计接口。例如 `GET /api/admin/workspace/organization/audit`。不支持任意代理路径。认证仍用原 `/api/auth/*`，只有ADMIN进入工作台；403/401清理页面会话。
- 该管理入口不改变Android/Flutter Web原公共业务接口的范围。FOUNDER不能仅凭创始人角色进入独立Web。不能用User-Agent、Origin或客户端自报角色替代服务端授权。
- V14 `log_first_submission_window` 允许撤回保留首次时间，已提交日志仍要求非空时间。不改V1–V13。C的新迁移需合并前确认编号；回滚不能直接恢复旧约束（撤回记录可能已有时间），不得清空首次时间来强行回滚。
- 日志评论 `POST /api/logs/{id}/comments`：text为1至2000字，可选parentId回复同一日志评论；返回id/actor_id/author_name/text/parent_id/created_at。所有已有日志可见权限的人可评论，24小时后仍可追加，禁止编辑删除。重复POST产生新评论（无幂等键），客户端避免自动重试。草稿403、不可见404、非法文本或回复目标400。GET返回同样字段，旧字段保留；不扩大同级或跨公司日志可见范围。通知日志作者及仍有权限的被回复人，同人去重，事务outbox不带正文。

## week6 Flutter 联调边界（2026-10-22）

本节为dc00e2b旧基线记录。2026-10-23 PR #33整合main 808d9d6后，新任务后端已提供participants、labelId、startAt与任务评论；客户端将HCJ别名映射为实际请求字段，任务评论需要幂等键，日志评论不需要。当前整合证据和未完成页面链路见docs/zhw-week6-main-integration.md。

- Flutter 下属日志查询可将 `departmentId`、`search`、`date`、`period` 与分页参数交给 `GET /logs/subordinates`；服务端仍负责部门和人员范围授权。`date` 是上海业务日期，客户端筛选控件不代表服务端权限。
- Flutter 将 `LOG_EDIT_WINDOW_EXPIRED` 映射为明确的不可修改/不可撤回提示。`submittedAt`、`editableUntil`、`canEdit`、`canWithdraw` 是展示提示；写操作仍以服务端响应为准。客户端当前修订使用审核申请流程，不宣称为 HCJ 所需的直接编辑。
- 当前后端任务契约仍接受 `ownerId`、`deadline`、`group`、`content`、`urgency`、`progressNote`、`collaborators`、`attachments`；详情以 `fields` 保存扩展内容。它没有 `startAt`、`participantIds`、`tagId`、标签分类/颜色权限和任务说明追加版本契约。因此移动端不能将这些 HCJ 字段伪装成已接入，也不能把静态标签映射视为服务端标签。真实任务新字段联调待后端提供契约后完成。
- 日志评论回复使用 `parentId`，客户端接受 HCJ 的 `parentCommentId` 并转换；读取保留 `id`、`authorName`、`parentCommentId`、`time` 和原始响应字段。日志评论发布没有幂等键，网络超时后客户端不得自动重放 POST；跨日志回复由服务端拒绝。任务评论接口仍未提供。
- `docs/openapi.json` 保持与当前 Spring 后端一致，不能用 HCJ 预期覆盖现有运行时契约。API 改变后应从后端 OpenAPI 重新生成并核对。
- 当前验证结果见 [历史文件](https://github.com/Ash123-star/Grade3_Work/blob/05d6c25b24d7b4304d8e4b1414adebee1f85fc38/docs/zhw-week6-validation.md)。新增 `withdraw` 操作使用 version/reason 调用独立撤回接口；未知直接编辑语义不转换成审核成功。任务新字段和任务评论调用在 HTTP 写入前明确失败。
- `GET /api/admin/workspace/organization/task-audit`（公共同权限入口`/api/organization/task-audit`）：仅ADMIN，taskId可选（最多100字）、cursor>=0、limit为1至100。返回items/total/nextCursor；条目包含审计原字段及actor_name/task_id。过滤任务直接事件、任务审核申请/决定及最终生效；数据库按公司过滤后计数分页。无权/未知taskId均空，非法分页400、非ADMIN403。无版本及幂等键，只读；Web任务审计入口支持翻页与前后值展示。
- 新增V15 `log_comment_replies`，旧评论parent_id为null，通过复合外键禁止跨日志回复。不修改旧迁移，不回删历史评论。
- 用户确认：标签模型与权限实际接入、C的新任务增删改审核联调等待C提供分支或契约。现有任务审计展示不代表新任务增删改闭环已经完成。

### 审核与通知业务展示（Issue #51）

GET /api/reviews/{id} 在现有审核读取权限校验之后追加 `display_references`：people、labels、departments、teams 分类下的 `{引用ID: 当前名称}`。只解析 before_value/candidate 内已有引用，查询必须限定 review_requests.company_id；缺失、已删除或跨公司引用不返回名称。该字段只供展示，不能提交为审核输入；原始快照、expected_version 及所有写入接口保持不变，无数据库迁移。名称反映读取时的当前名称，不能当作历史名称证据。

移动端将审核快照显示为中文业务字段；时间按 Asia/Shanghai 展示，附件显示数量；缺失引用显示“名称暂不可用”，不回退内部ID。创建申请无“当前生效v0”，通过/驳回/失效记录无待审生效提示。GET /notifications 的 type/object_id 保持现有契约：历史 TASK_DISPATCHED 与 TASK_ASSIGNED 均显示收到新任务并指向 tasks；TASK_EVENT/REVISED/REASSIGNED/RESCHEDULED/COMMENT、DEADLINE、DELIVERY_CHECKED 指向 tasks；LOG_SUBMITTED/UPDATED/COMMENT 指向 logs；REVIEW_PENDING/APPROVED/REJECTED 指向 reviews；AI_READY 指向既有作业结果页，AI_WORK_UPDATED 指向工作详情页。未知类型显示“工作通知”，缺失或不支持目标明确提示；目标详情仍执行既有服务端权限校验，不新增旧接口或绕过鉴权。标记已读的网络失败保留错误提示并允许打开合法详情，401/403仍阻断。

### 组织团队名称与操作反馈（Issue #52）
GET /organization/people沿用原组织数据范围，追加可空team_name，按teams.id及company_id联合关联；无团队或名称不存在时返回null。客户端将team_name/嵌套team.name归一化为teamName；统计筛选优先取当前授权组织树teams名称，不将team_id当显示名称。无需数据库迁移，旧客户端可忽略新增字段。任务和组织查询权限保持现有规则。
