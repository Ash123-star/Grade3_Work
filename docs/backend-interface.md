> 当前审核规则（2026-11-06）：创始人权限内非MEMBERSHIP新操作免审，不因多创始人互审；部门经理仅由当前有效直属上级审批，其他创始人不可代审。V32作废旧FOUNDER_PEER待审及待审步骤并留审计/通知，必须重新提交，禁止reroute恢复或更换审核人；已决历史保留。MEMBERSHIP继续管理员确认。下文V28互审描述仅为历史，当前规格见openspec/changes/multi-founder-review/specs/multi-founder-review/spec.md。

# 后端接口文档

## OSS文件与公开素材

Issue #79 / OpenSpec `unified-oss-resource-storage`：上传文件正文统一写入私有OSS，历史bytea在迁移前兼容读取，附件ID不变。`POST /api/attachments`原multipart契约及10MB/AI用途限制不变，只有对象写入、读回哈希校验和READY元数据提交后返回成功；`GET /api/attachments/{id}`每次检查当前身份/公司/业务范围，禁止公开URL和共享缓存。503 `STORAGE_UNAVAILABLE`、502 `FILE_INTEGRITY_ERROR`、404 `FILE_NOT_FOUND`均保留统一错误及traceId，不返回供应商异常或凭据。

CSV导出和模板预填文件先持久化OSS再通过原接口返回，CSV额外响应头 `X-Generated-File-Id`。新增 `GET /api/generated-files/{id}`仅允许同公司本人且来源仍授权/版本有效时下载；默认24小时过期，404过期/不存在、403越权、409 `SOURCE_CHANGED`。附件兼容入口也重验生成文件来源。生成不修改业务版本，重复生成可产生新文件，无幂等键要求。

新增公开只读 `GET /api/assets/manifest`（当前完整版本清单，ETag/304、无版本404）和 `GET /api/assets/{release}/{*path}`（已发布白名单静态文件，内容类型、哈希ETag及不可变缓存）。仅用于产品图片/SVG/纹理/字体/许可证，不接受任意OSS Key、Bucket或URL；非法/未发布/目录穿越路径拒绝，不授予业务文件访问权。原生启动必需资源保留安装副本，运行时客户端经统一资源加载器访问并校验/缓存。部署、历史迁移和回滚见 `docs/oss-storage.md`。

## 契约来源与通用约定

实现事实以 SpringDoc 运行时文档 `GET /api/openapi` 为准；提交到仓库的 `docs/openapi.json` 是同一份契约快照，本文件只解释调用规则。三者必须同步更新，客户端不得根据旧版本猜测字段。

`docs/openapi.json`包含每日事项等运行时契约；快照生成和专项测试均有提交/环境范围。最新已记录完整自动化及未验设备/外部依赖统一见 [验证入口](backend-validation.md)，不把旧批次失败或快照刷新等同当前验收结论。

根路径为 `/api`。除公开登录、注册和健康检查外均需 `Authorization: Bearer <session-token>`。每个响应带 `X-Trace-Id`；错误体为 `{code,message,traceId}`。列表使用 `{items,total,nextCursor}`，`cursor` 为偏移量，`limit` 范围 1–100。时间使用 UTC ISO-8601，业务日期按 `Asia/Shanghai` 且周一为周首。

[移动端补充快照](mobile-openapi-contract.yaml)保存历史补充契约，不覆盖Controller/运行时SpringDoc，也不独立维护完成度。其旧IMPLEMENTED_UNVERIFIED标签与“尚未编译/迁移”的结论已过期；状态统一见 [接口接入与待验收](backend-interface-gaps.md) 及验证入口。接口变化须同步运行时SpringDoc、OpenAPI、调用方和契约测试。

移动端与服务端的逐项缺口、当前实现状态和后端接手验收要求见 [`docs/backend-interface-gaps.md`](backend-interface-gaps.md)。其中“缺失/不匹配”只表示协议或运行端点尚未兑现，不表示移动端 Mock 已替代服务端业务。

写请求只接受文档列出的字段。更新请求携带 `version`；创建请求可携带 `Idempotency-Key`。版本冲突返回 `409`，越权对象通常返回 `404`，明确的人员筛选越权返回 `403`。

每日事项与首页任务看板新增契约见 [personal-todos-interface.md](personal-todos-interface.md)（Issue #63）。事项仅本人可见，所有写请求必须有幂等键；该约束比下文通用创建规则更严格。

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

组织树和 `/people` 返回范围内数据。人员目录项增加可空 `employmentStartDate`（真实入职日期，YYYY-MM-DD），沿用原组织查询权限，无新增表或接口。移动端点击授权员工可展示入职日期及按上海业务日计算的工龄；缺失/未来日期不从注册时间推测。管理员策略、人员和组织单元的关键变更使用 `version`、`reason`，通过审核后生效。主要接口：`GET /organization`、`GET /organization/departments`、`GET /organization/people`、`POST /organization/membership-application`、`GET/POST /organization/review-policy`、`POST /organization/reviewer-application`、`POST /organization/users/{id}/revisions`、`POST /organization/{departments|teams}/revisions`、`GET /organization/audit`。

## 任务 `/tasks`

2026-10-30（Issue #49）：`GET /tasks/received-card` 仅返回当前用户本人参与的任务（包括本人派发且参与），包含全部生命周期状态，不再返回仅下属参与的授权范围任务。`items/total/nextCursor`使用相同过滤；每项增加`issuer_id`。导图卡片与完整列表共用该资源，管理任务表继续使用`GET /tasks`授权范围查询。

`GET /tasks` 使用显式授权投影，不返回主负责人或协作人；参与人使用无角色的 `participants` 集合，标签以本文“统一集成兼容约定”的 `labels` 集合及旧 `label` 兼容规则为准。流转事件在 `GET /tasks/{id}` 的 `events` 中返回。`POST /tasks` 提交创建审核，需 `title,participants,deadline`、可选 `startAt,labelId,labelIds,attachments,acceptanceChecklist` 和 `Idempotency-Key`；审核批准后才产生正式任务，同键重放返回同一审核申请。

**2026-11-05实现增量（部署与验证状态另见统一验证入口）**：复用Issue #53确认的可选只读 `phase`，任务管理在开始时间前展示完成情况，派发表单仍不显示或接收该字段。映射为 `DISPATCHED` 待接收、`RECEIVED` 进行中、`FEEDBACK` 待验收、`ACCEPTED` 已验收、`ARCHIVED` 已归档、`WITHDRAWN` 已撤回；`RETURNED`是事件，生效后phase为RECEIVED。缺失/未知显示“情况未知”，不从截止时间、备注或任一参与人反馈推断。另返回可空 `dispatchAt`，取同公司同任务最早真实DISPATCHED事件时间，旧数据缺失为null，不能拿created_at伪造派发时间。增量字段向后兼容，旧客户端可忽略，新客户端连接旧服务端时显示未知/未提供；列表授权范围、分页与审核政策不变，不暴露未过滤body/事件。任务状态只读，创建/修订伪造状态仍由服务端拒绝。验收见 [A03](app-requirements-acceptance.md)。

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

本人及下属日志列表在指定起止时间时均发送成对的`from/to`，移除互斥的`date/period`。近三天为上海前天零点至明天零点的左闭右开区间；例如2026年11月6日发送`2026-11-03T16:00:00Z`至`2026-11-06T16:00:00Z`，不得将三天区间转换成前天的单日查询。提交后沿用既有日志列表失效刷新，不需要修改后端或重新提交已保存日志。

## 审核 `/reviews`

`PUT /tasks/{id}/pin`、`DELETE /tasks/{id}/pin` 为个人置顶：调用者须能读取该任务（范围外404），只影响本人 `GET /tasks` 排序（置顶优先、最近置顶在前，其后按截止时间），列表项增加 `pinned`/`pinnedAt`；不改变任务 version、不走审核、不写通知。每人最多10项（仅计仍可见任务），超出409 `PIN_LIMIT`；重复置顶返回原 `pinnedAt`，取消未置顶任务也返回成功。日历、导图公司任务卡和已接收任务卡不受置顶影响。

`GET /reviews`、`GET /reviews/{id}` 返回申请人或当前仍有权的分配审核人可见内容，包含尚有当前权限的已决历史，SUPERSEDED步骤不提供读取权限。`POST /reviews/{id}/decision` 请求 `{approve,reason,expectedVersion}`，驳回须理由，禁止自审并复核目标版本及当前直属关系。除 `MEMBERSHIP` 管理员确认外，使用 `DIRECT_MANAGER` 单级审核；创始人发起时，若同公司另有在职创始人则使用 `FOUNDER_PEER`：默认分配直属上级（若为在职创始人）或 id 最小的其他在职创始人，决定时复核审核人仍为在职创始人，成功记录 `decision_source=FOUNDER_PEER`；公司仅一位在职创始人时，其权限内新操作自动批准并记录 `FOUNDER_EXEMPT`。管理员不免审，也不因任何兜底获得审批权。无审核人保持待审，并向申请人和在职管理员发送去重的 `REVIEW_UNASSIGNED`。决定与改派均锁定申请行并以 `PENDING` 条件更新，重复或并发决定只生效一次，其余返回409。详情增加 `reviewer_selectable`（仅本人 PENDING 的 FOUNDER_PEER 为 true）。`GET /reviews/{id}/reviewer-candidates` 仅申请人可读，返回 `{items:[{id,name,current}]}`；`POST /reviews/{id}/reviewer` 请求 `{reviewerId,expectedVersion}`，非在职其他创始人400 `INVALID_REVIEWER`，非申请人403，已决/版本不符409，非 FOUNDER_PEER 409 `REVIEWER_SELECTION_UNSUPPORTED`，重复选择当前审核人返回原详情；原步骤SUPERSEDED并记录 `REVIEW_REVIEWER_CHANGED`。组织 `USER`（停用、改角色、改直属上级）或 `REVIEWER` 变更生效时，同一事务内复核本公司其他待审申请：审核人失效则作废并按当前规则重新分配，记录 `REVIEW_AUTO_REROUTED`；正被其他事务锁定的申请跳过，由该事务按最新关系校验。仅剩一位创始人时不自动免审，需申请人显式 reroute。`POST /reviews/{id}/reroute` 仅申请人继续PENDING申请，保留已决历史、替代待审步骤；有效创始人明确继续本人非MEMBERSHIP申请时，才按当前业务权限和目标版本免审应用，重复已免审请求返回原结果。迁移不会自动应用任何历史候选。

## 仪表盘、通知、分析和附件

仪表盘提供 `/dashboard`、`/dashboard/company`、`/dashboard/personal`、`/profiles/{id}` 和 `/private-notes`；私人备注始终仅本人可见。`PUT /profiles/me` 的移动端协议字段为 `introduction/phone/email/gender/age/avatarAttachmentId/version`，姓名、部门、职位、角色和状态只读。通知提供 `GET /notifications`、`POST /notifications/read-all`、`POST /notifications/{id}/read` 和支持 `Last-Event-ID` 的 `/notifications/stream`。分析提供 `/analytics`、`/analytics/details`、`/timeline` 和 `/analytics/export`；汇总、钻取与 CSV 必须共用 `groupBy/departmentId/teamId/ownerId`、日期窗口和权限范围。附件 `POST /attachments` 使用 multipart，单文件最大 10MB；`GET /attachments/{id}` 每次重新鉴权，不提供公开 URL。

通知读取沿用`cursor/limit/type`，新增可选`category`（任务/审批/评论/待阅提醒/截止提醒/审核结果）、`unreadOnly`（默认false）、`search`（最多200字，按中文通知标题及当前可读目标摘要搜索）。过滤在分页与计数之前执行，响应保留`items/total/nextCursor/unread`；末页`nextCursor=null`，`unread`为本人全量未读数，不受分类、搜索及已加载页数影响。每项新增`message_title/summary`：任务标题复用TaskAccess，日志摘要复用本人或已提交日志的组织/直属范围，审核摘要复用当前申请人/有效审核人范围；不可读目标仅显示通用不可用提示，不能因为收到消息而读取目标标题。客户端首屏30条，显式加载更多，移除逐消息详情HTTP补读；首页和个人页共用首屏及全量未读数。旧客户端仍可读取原字段；新客户端的历史筛选和摘要须先部署新版服务端。

业务安全限额保持同账号120次/60秒，429返回Retry-After（至少1秒）。客户端不再合成本地429拒绝其他业务操作；仅后台同步调度遵循真实429的Retry-After或默认60秒延后，不重放写入。消息页按会话和筛选条件缓存已加载分页，离页保留5分钟、重新进入先显示缓存；有订阅且在前台时每30秒静默核对，无订阅或后台暂停，相同请求合并。GET /notifications支持If-None-Match，实时授权及查询后按当前分页/摘要/未读数生成用户隔离的弱ETag；匹配304无响应体，Cache-Control: private, no-cache，Vary: Authorization。CORS允许If-None-Match并暴露ETag。客户端304复用缓存对象，普通失败不覆盖已有列表；显式重试失败显示操作错误，401/403丢弃旧内容。SSE只负责其他业务定向事件，首次连接先获取本人最新sequence跳过历史重放，后续按序号断线恢复，不驱动消息页重复失效。前台常规身份校验静默进行，身份/权限未变不替换会话，退出/切号/权限变化销毁缓存；缓存仅在内存，最末已加载历史页亦按条件GET重新验证。

## AI `/ai`

`POST /ai/jobs` 创建异步草稿，`GET/DELETE /ai/jobs/{id}` 查询或取消，`POST /ai/jobs/{id}/retry` 重试，`PUT /ai/jobs/{id}/draft` 按版本编辑，`GET /ai/jobs/{id}/stream` 读取 SSE，`GET /ai/usage` 查看用量。`GET /ai-maps` 和 `POST /ai-maps/edges` 管理本人范围内地图。`POST /ai/jobs/{id}/confirm-task` 必须带幂等键，确认后重新走任务派发权限和事务；AI 失败返回 job 状态，不影响普通任务和日志。

## Flutter 接口缺口（待完成）

2026-10-29剩余接口实现状态见 [统一接入状态](backend-interface-gaps.md)。任务评论/日志回复和RETURNED后端已存在，本批接通客户端退回及通知映射；成果反馈增加最多5个attachments（仅本人上传同公司可用材料，复用任务读取授权）。`GET /organization/teams`返回当前组织树范围内团队目录。意见反馈已由用户取消，移动端入口/表单/Mock资源移除，旧深链返回帮助页；不新增feedback接口。阅读登记已停用，不新增阅读人员清单。

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


## 公司月历整段移动（Issue #58，V27）

- `GET /tasks?from=<ISO带时区>&to=<ISO带时区>` 返回区间相交的完整范围分页；窗口≤62日、记录≤5000。新响应含 `snapshotToken`、`scheduleConstraints`、`capabilities.reschedule`；末页 `nextCursor=null`。新月历后续页带原快照，变化返回409 `CALENDAR_SNAPSHOT_CHANGED`。旧客户端无快照仍可分页；参与人 `ownerId`/`participantId` 别名及当前 `date/period` 相交规则不变。
- `POST /tasks/{id}/reschedules` 新模式仅接受 `{version,moveDays,reason}`：version正int32，moveDays非零int32，reason去空白后1–1000码点。头部 `Idempotency-Key` 为1–128可见ASCII字符；`If-Schedule-Constraints-Match` 使用服务端约束版本。服务端按上海业务日同时移动开始/截止时间，保持时长及其他业务字段。
- 仅有当前派发资格的原派发人或管理员可申请；客户端能力是提示，服务端每次重验。提交返回审核记录，待审原排期不变。审核继续使用 `expectedVersion`；权限变化/版本冲突拒绝，禁止自审，采用现有审核策略。
- 相同键相同内容返回同一审核结果；不同内容409 `IDEMPOTENCY_CONFLICT`，同任务同版本不同键待审409 `RESCHEDULE_PENDING`。旧版仅 `deadline/version/reason` 请求保持兼容。关闭移动开关后仍可重放已有命令。
- `scheduleConstraints` 定义上海业务年Y的日期窗口 `[Y-2年01-01,Y+8年01-01]`；头过期409 `SCHEDULE_CONSTRAINTS_CHANGED`。快捷创建沿用 `/tasks`，带约束头时校验窗口，不带头的既有创建不新增限制。
- V27只新增改期命令表和索引；已发布迁移不变。部署全部MOVE审核消费者后设置 `CALENDAR_MOVE_ENABLED=true`；存在待审MOVE时禁止回滚至不理解MOVE的旧服务端。

### 统一集成兼容约定（2026-11-04）

正式迁移顺序为 V27 日历、V28 创始人互审、V29 个人置顶、V30 多标签；旧 PR 的 V24/V25 为未发布编号。任务创建可以省略 labelIds 或传空集合；旧 labelId 与相同单元素集合兼容，双字段冲突返回 400 LABEL_CONTRACT_CONFLICT。列表和详情增加 labels、保留旧 label。升级前零/单标签请求的原幂等键仍可重放；增加或更换标签不得复用原键。

管理后台 POST /admin/workspace/management/reviews/{id}/decision 采用 {approve,reason,expectedVersion}，与公共审核使用同一版本和独立审核校验；缺失版本400、版本冲突409、自审或非分配审核人403。

### 中国大陆节假日月历（成员 D）
`GET /api/calendar/holidays?year=2026`：已登录、已确认且无需强制改密的账号可读；沿用公共认证规则。year为2007至2100，越界400 `INVALID_YEAR`；缺失/格式错误400；未登录401、无业务访问权限403。只读幂等，无写入版本及分页。返回 `{year,days:[{date,name,isOffDay}],papers,status,fetchedAt}`；date为中国大陆业务日期，isOffDay=false表示公告指定的调休上班日。status为FRESH、STALE或UNAVAILABLE；fetchedAt为最后成功获取的UTC时间，无成功记录为空字符串。
固定来源为同一 NateScarlet/holiday-cn 仓库：GitHub Contents API（raw Accept）优先，raw.githubusercontent.com 原始文件兜底，保留国务院公告链接。缓存24小时；两入口均失败时5分钟重试间隔，保留最后有效内容，首次失败返回空days及UNAVAILABLE，不伪造假期。同年请求合并、不同年份独立加载。客户端查询相邻公告年份处理跨年网格，提示仅针对可见年份；数据故障不阻塞任务。每入口仅请求一次、各3秒，合计请求预算6秒，流式响应上限256 KiB，连接超时2秒；中断立即停止。无密钥、无新增迁移。此接口不提供其他国家/地区、节气或任务修改能力。
