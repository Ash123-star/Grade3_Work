# 前端接口草案

## 2026-10-23 任务显示元数据

派发和修改沿用 `tagId`、`participantIds` 标识；任务读响应应同时返回 `tagName` 和与ID顺序一致的 `participantNames`，或包含真实姓名的participants对象列表。适配层接受camelCase与snake_case。显示名不参与权限判断；内置标签ID统一映射中文，未知标签且无名称显示“标签名称未提供”，缺失成员姓名显示“成员姓名未提供”，不得把ID当姓名或查询越权人员补名。Mock按已有演示组织的真实姓名补全新建和历史任务，只是本地显示契约，不证明真实服务联调通过。

本契约用于 UI 框架接入，尚非已经上线的服务。所有请求使用 HTTPS；认证后附加 Bearer token，服务端再次验证 company_id、角色和对象范围。客户端不接收 DeepSeek 密钥。

## 2026-10-13 接口交接状态

下文“通用协议”和页面表为早期 UI 草案，不是当前服务端全部已实现的协议。实际请求以 `lib/data/repositories/repository.dart`、`ai_repository.dart` 和 `server/src/main/java/cn/workpanel/module/` 为准；五个主路由为 `/dashboard`、`/view`、`/logs`、`/ai`、`/me`。布局与已有接口接入未新增API/数据库；本地测试和实际Flutter渲染只证明对应客户端链路，不证明已上线或真实数据库/设备验收。

| 对象 | 核对出的实际边界 | 交接待办 |
|---|---|---|
| 私人备注 | GET/PUT `/private-notes` 已存在；GET 仅本人，UUID 与对象 resource/object_id 不同；PUT resource/objectId/text/version，仅 tasks 和 dashboard/company | 客户端已按资源、对象 ID、本人账号匹配返回备注，并以 objectId、text、version 调用 PUT；个人重点备注仍不在服务器支持范围。HTTP 契约测试已覆盖，真实数据库/权限仍需联调。 |
| 本人资料 | PUT `/profiles/me` 支持 introduction/avatarAttachmentId/version | 姓名只读；客户端读取嵌套profile，保留现有介绍与版本，支持已有POST附件上传获取实际新头像ID和受认证字节显示。HTTP/UI测试通过，真实设备与服务待联调。 |
| 历史版本/评语 | 已提交日志独立 GET `/logs/{id}/versions` 与 `/comments`；版本正文与当前正文分离 | 客户端已映射真实正文、作者ID和时间。局部网络错误可重试；401/403清除受保护正文。HTTP/UI测试通过，真实服务仍待联调。 |
| 日志阅读登记 | 显式POST `/logs/{id}/read`，请求空对象，响应`{"ok":true}`；只有已提交且有权阅读的日志可登记，不修改正文/version。GET详情/历史无登记副作用 | 客户端精确编码非空ID、严格确认、忙碌锁/失败重试/401403整页清理及旧会话隔离已通过13项HTTP/UI测试。GET日志不返回阅读人员清单，且没有read-list GET；缺失说明不可用，不能以本次POST推断其他人已读。`submitted_at`仅实际返回时展示上海时间；真实服务/数据库仍未联调。 |
| 重点详情 | 服务端仅有公司/个人重点分页列表，没有单对象 GET | 客户端从授权分页定位ID，成员个人重点保留ownerId上下文；缺失或403明确恢复，不代用首项。 |
| 任务/通知读取 | 任务列表仅返回参与人、标签、带时区时间和安全投影；详情含时间线；通知字段is_read/recipient_id/type/object_id | 客户端读取 `participants`、服务端标签颜色、`start_at` 与 `deadline`；详情按事件恢复既有操作，列表不接收或展示完成情况、阶段或替代状态字段。通知仅已知类型跳转真实目标。 |
| 任务变更 | 创建、通用修改和删除均提交审核申请；评论为公开只追加记录 | 客户端创建/修改发送 `participants`、可选 `labelId`、`startAt` 和带时区 `deadline`，不发送 `ownerId`、`collaborators` 或 `progressNote`；创建响应是待审申请，不能当作正式任务使用。任务评论用独立 `/tasks/{id}/comments` 并携带幂等键；标签接口为 `/task-labels`。 |
| 认证状态 | 登录返回status/must_change_password/expiresAt；GET auth/me；改密撤销全部会话，logout撤销当前会话 | 客户端已接待确认刷新、强制改密、到期/明确会话错误跳转、服务端退出和前台验证。原生安全凭证/启动me验证已接；验证前不挂载业务。网络失败明确重试，401/身份变化清理；普通对象403不误退出。真实Keystore/服务撤销仍待联调。 |
| AI/上传/导出/反馈 | 正式AI作业、受控附件及同步CSV已有服务端契约；支持反馈尚无契约。当前反馈列表通用映射可能请求 `GET /feedback`、详情可能请求 `GET /feedback/{id}`，但后端没有对应 Controller | AI/附件/导出客户端接入及HTTP/UI测试，详见下方；支持反馈查询/提交、真实服务/设备链路仍未完成。集中缺口登记见 [backend-interface-gaps.md](../../docs/backend-interface-gaps.md)。 |

详细本地命令与证据见 [阶段3验收](stage-3-verification.md)。这些未完成项保留在独立变更的验收边界与本地 Issue 中，不宣称生产业务完成。

## 通用协议（历史 UI 草案）

GET /{resource} 接收 search、cursor、limit、ownerId、from、to，返回 `{items: Record[], total, nextCursor}`。时间为 UTC ISO8601，from 包含、to 不包含；业务时区 Asia/Shanghai，周一为周首。

GET /{resource}/{id} 返回 Record。Record 包含 id、title、subtitle、ownerId、version、fields。fields 是本阶段 UI 聚合展示数据；接后端时在 data 层映射成正式领域 DTO，widget 不解析 HTTP JSON。

POST /{resource} 接收 `{action, values, version?}`，修改命令在 values 中带 id。创建和提交请求可携带 Idempotency-Key；重要修改携带当前 version。响应为 Record；审批响应应同时区分生效版本和候选版本。服务端返回 409 时客户端保留输入、提示刷新，不能盲目覆盖。

统一失败覆盖 400/422 表单校验、401 登录失效、403 无权限、404 不存在、409 版本冲突、超时与 5xx；响应头可带 x-trace-id。错误日志不得记录密码、访问令牌、私人备注和 AI 密钥。

## 页面与接口

完整的页面、操作、接口状态和后端实现输入见 [`api-surface-coverage.md`](api-surface-coverage.md)。本文件以下内容描述已确认的通用请求规则；待定契约不代表已有可调用 URL。

| 页面入口 | resource | action / 行为 |
| --- | --- | --- |
| /form/login、register、password | auth | login/register/password，注册不允许 role 参数 |
| 导图公司重点 | dashboard/company | 只读列表；独立 publish 入口 request-review |
| 个人重点 | dashboard/personal | create/update/archive，排序由字段传递 |
| /form/note | private-notes | save，服务端仅返回本人备注 |
| /list/tasks、任务详情 | tasks | create/receive/feedback/accept/transfer/reschedule/withdraw |
| 日志和时间视图 | logs | submit/request-review，user+businessDate 唯一 |
| 下属日志 | logs/subordinates | ownerId 限于管理范围 |
| 评语和历史 | logs/comments、logs/{id}/versions | comment；历史接口待按服务端映射 |
| 审批中心 | reviews | approve/reject，自审禁止，reject reason 必填 |
| 组织和管理页面 | organization、organization/admin | 部门、归属、角色、汇报关系、停用、策略 |
| 消息 | notifications | read-all；详情按业务对象跳转 |
| 分析、导出 | analytics、analytics/export | 当前区间和范围，导出结果不得越权 |
| AI 地图 | ai-maps、ai | summarize，建议包含来源和生成时间 |

任务表单必填 `title`、`participants`、带时区 `deadline`；参与人是无角色且去重的集合，不再有主负责人或协作人语义。可选字段为 `startAt`、`labelId`、`group`、`content`、`urgency`、附件和验收清单。派发页不显示完成情况字段，任务列表也不得返回完成情况或替代状态字段；流转事件仅在详情时间线中读取。API 日期字段转换使用 UTC，显示采用业务日期。

## 已接入与待定的异步边界

附件已接POST `/attachments` multipart file，1字节至10MB，返回id/filename/size；任务提交引用实际ID，GET `/attachments/{id}`受认证字节保存，使用Content-Disposition安全文件名。头像保存同样引用实际上传ID。未有DELETE接口，移除表单文件不代表服务端清理；成果反馈接口不支持附件关联时禁用上传。真实设备文件对话框/服务未验收。

通知 SSE 已由服务端 `GET /notifications/stream` 和 Flutter `NotificationStream` 接入；事件携带 id/sequence，支持 Last-Event-ID 重连。客户端按序号刷新列表，服务端事务 outbox 负责最终投递。AI 作业 SSE 使用独立 `/ai/jobs/{id}/stream`。

正式 AI 已有客户端接入：POST `/ai/jobs`、GET `/ai/jobs/{id}`、DELETE 取消、POST retry、PUT draft、GET stream、POST confirm-task、GET usage 及 GET/POST 地图，详细见下方。演示固定样例不调用外部模型。AI 范围选择和确认 job 版本原子保护仍是待定契约。导出使用已有同步 CSV GET `/analytics/export` 和实际字节保存，无异步 job 或短期 URL 契约。

## 界面范围

五栏：/profile、/ai、/logs、/calendar、/dashboard。辅助路由：/list/:resource、/item/:resource/:id、/form/:kind、/settings、/admin、/pending、/disabled、/expired、/privacy、/licenses、/history、/conflict、/report、/ai-usage、/export。具体表单由 features/catalog.dart 维护。

## 阶段3既有组织与统计接口对齐（2026-10-13）

客户端组织浏览使用GET /organization的实际departments/teams和GET /organization/people全部分页；tree.users只是服务端首批页，不能视为完整成员。成员详情GET /profiles/{id}返回公开资料、用户version与当前dispatch_enabled/company_reviewer；未返回manager_id时客户端不猜旧汇报关系。

组织修改不立即PUT：POST /organization/{departments|teams}/revisions提交id/name/团队departmentId/version/reason（新建version0）；POST /organization/users/{id}/revisions仅发送本页修改的role/status/departmentId/teamId/dispatchEnabled/companyReviewer/managerId及实际version/reason，未指定字段由服务端保留。GET /organization/review-policy读取version/review_policy；POST /organization/review-policy/revisions仅两个任务开关taskTeamReview/taskDepartmentReview与version/reason。公司复核资格为人员字段，不是策略复核人ID。全部沿用服务端独立复核/组织范围/最终管理员等限制。

GET /organization/audit仅分页列表，单条详情从授权页定位，字段type/actor_id/object_id/before_value/after_value/reason/created_at；不调用不存在的GET单条接口。

GET /analytics必须date(YYYY-MM-DD)/period(day|week|month)，返回单个对象，包含dispatched/overdue、onTimeAcceptance与dailySubmission（numerator/denominator/rate/definition）、departmentDistribution、unreadLogs、updatedAt、range；不是items列表，无部门/人员过滤或趋势明细契约。GET /analytics/export沿用同date/period及resource(logs|tasks)，响应原始CSV字节，权限与统计范围一致；客户端saveFile(bytes)成功返回路径后才显示保存成功。接口已有，不新增服务器/数据库迁移。

## 阶段3既有AI契约对齐（2026-10-13）

正式页面使用专用AiRepository/模型，通过当前HttpRepository的认证Dio调用企业服务，客户端不调用DeepSeek或保存供应商密钥。POST `/ai/jobs`只含date、period(day/week/month)、purpose(SUMMARY/EXPLAIN_RISK/SPLIT_STEPS/DRAFT_TASK)、可选focusSourceId；非SUMMARY必须有有效来源。接口没有ownerId或scope筛选参数，范围来自服务端Actor；正式页展示真实授权范围，不提供无效个人/公司切换。服务器来源可包含50日志+50任务+10个人重点。

GET job返回id/owner_id/state/input/output/version/error/created_at等嵌套数据，状态QUEUED/RUNNING/SUCCEEDED/FAILED/CANCELLED。output有summary/sourceIds、最多10 nodes和3 actions、generatedAt/draft；建议引用必须能与input.sources匹配。服务端验证当前来源权限。客户端将匹配的task/log/item来源映射到内部详情，只允许无外部host/scheme的准确路径；个人重点保持本人ownerId上下文，不跳任意URL。来源不足禁确认。

GET `/ai/jobs/{id}/stream`为受认证SSE，delta.text是累计的未完成JSON，不作为可操作建议；result事件后或流断开后GET核实最终作业。支持UTF8跨块、CRLF、多行data、keepalive、边界大小；回页可“继续接收”同作业而不再次生成。取消只有显式DELETE，离页/换账号仅取消传输，不假称远程取消；POST retry沿用原输入并返回新job ID。503 AI_NOT_CONFIGURED、429 AI_BUDGET及网络失败保留输入/上次结果；403/401或账户变化清除页面、弹窗受保护来源。

PUT `/ai/jobs/{id}/draft`只发送version/summary/sourceIds/nodes/actions，保留来源、node和ownerId，编辑正文及建议标题；409保留输入并禁过期提交，确认重新读取后替换。保存草稿不创建任务。POST `/ai/jobs/{id}/confirm-task`必须派发资格与Idempotency-Key，body为actionIndex/task。专用确认页人工编辑title/content/group/progressNote/urgency、实际单负责人、协作人、附件ID与未来deadline，确认前GET核对job版本/来源；相同载荷重试保持幂等键，修改载荷重新确认并换键。服务端确认没有version字段，GET与POST之间仍有远程编辑竞态，不能声称原子版本保护。

GET `/ai-maps`返回实际nodes(id/job_id/owner_id/body)/edges(source_id/target_id/body)，客户端读取关联job恢复来源，带过滤/缩放/列表替代；POST `/ai-maps/edges`提交sourceId/targetId/label，禁止自身依赖。GET `/ai/usage`只有dailyLimit及UTC日期tokens/jobs记录，客户端不猜用量。未新增后端、数据库或依赖，真实供应商/数据库/设备链路仍待验收。
