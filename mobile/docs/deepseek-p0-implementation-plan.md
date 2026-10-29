# DeepSeek 开发任务书：P0 前后端契约与审核改造

更新日期：2026-10-29（Asia/Shanghai）
关联 OpenSpec：`openspec/changes/mobile-page-experience-refresh/`
本地追踪：`docs/issues/mobile-page-experience-refresh.md`

## 任务目标与当前状态

目标是让 Flutter 实际请求、Spring 运行时代码、PostgreSQL 数据及 OpenAPI 契约一致，完成以下六组 P0 链路：接收任务卡片、任务时间区间、下属日志筛选/月状态、已提交日志正文直改、统计汇总/钻取/导出、本人资料读写；并完成 #17 直属上级单级审核及创始人权限内免审。

当前分支为 `HCJ`。当前工作区已有未提交代码草案，包括 `TaskQueryService`、`LogQueryService`、`LogWorkflowService`、`DashboardController`、审核服务及未跟踪的 V22 迁移。这些改动**没有通过编译、测试或真实数据库联调**。先检查 HEAD、`git status --short` 和完整 diff；把现有草案当作待审实现，不要按旧审计表把它们误判为“仍完全不存在”，也不要整体重写或覆盖。

`mobile/handoff.md` 的接口对照表记录的是 2026-10-29 开始审计时的运行基线。它之后已经有上述未验证草案，因此该表用于说明原始缺口，不作为当前工作区状态。必须以本次实际 Git diff、Controller、服务、Repository、迁移和 Flutter HTTP 调用重新核对。

## 固定产品规则

- 只做本任务书列出的 P0 与 #17，不扩展 P1 评论、退回、反馈或额外 UI 重构。
- `MEMBERSHIP` 注册成员确认继续由管理员审批；不得转直属审核，不得创始人免审。
- 其他适用的关键审核由当前有效直属上级单级审核。没有有效直属上级时保持待审，不自动通过、不按职位猜人。禁止自审；驳回必须有理由；决定必须校验版本。
- 创始人只对自己原本有权执行的非 `MEMBERSHIP` 修改免审；在同一事务中应用修改并写 `APPROVED`、`FOUNDER_EXEMPT`、审计及 outbox。不得扩大业务写权限。
- 迁移保留历史记录；禁止自动应用任何历史待审候选。历史待审步骤应显式失效/替代，再按当前规则路由；已决步骤仅作审计历史。
- `users.phone` 是唯一权威手机号；新增 `email`、`gender`、`age`、`employment_start_date` 列。简介及头像仍存 `profile` JSONB。选填资料允许清空；手机号清空时列允许 NULL，但唯一约束保留。新注册是否仍要求提供手机号遵守现行注册契约，不因本接口改动而放宽。
- 性别按现有移动端和草案契约作为最多 32 字的自由文本；年龄非负、不增设年龄上限。邮箱按格式和长度校验。姓名、部门、职位、角色等组织身份字段只读。
- 旧员工无可靠入职日期时保持 NULL，月状态按规则返回 `UNKNOWN`；不得用 `created_at` 或迁移日补猜。新成员在管理员确认生效事务中写入上海业务日期。
- 公司任务可见范围沿用产品已确认的当前任务授权范围，不得为了“received”字样擅自缩小到某个角色或仅任务 owner；派发时间必须来自真实 `DISPATCHED` 事件，不能从截止时间推算。
- 数据列表、详情、筛选、统计、导出及资料都必须服务端按当前组织关系和数据范围授权；失权后不能依赖旧缓存继续访问。

## 公共契约约定

- Spring 路由路径以 `/api` 为前缀；HTTP 适配器只做协议映射、Actor/参数解析和响应，不写业务 SQL。SQL 留在当前模块 Repository/查询层，事务和规则留在应用服务。
- JSON 错误使用项目统一错误信封。至少区分 400 参数/字段错误、401 未认证、403 越权、404 不存在或不可见、409 版本/唯一键/状态冲突。错误码稳定、可测试；不要把无权筛选静默忽略后返回更宽数据。
- 分页沿用当前 `cursor` 非负 offset 与 `limit` 1–100 的兼容方式，响应形状 `{items,total,nextCursor}`；排序必须有唯一 ID 作为最终 tie-breaker。检查 Flutter `Query.cursor` / `PageResult.nextCursor` 实际类型后统一编码，不能只改 YAML。
- `from/to` 是带时区 ISO-8601 instant，`from` 含、`to` 不含；只允许同时出现。若提供 `from/to`，不得同时提供 `date/period`。旧 `date/period` 仍兼容。上海自然日/月状态使用 `Asia/Shanghai`，不得用服务器默认时区。
- 移动端任务查询目前把 `Query.ownerId` 编码成 `participantId`；任务筛选的规范含义是“任务参与人”。服务端接受规范参数 `participantId`，并为兼容接受 `ownerId` 别名；两者同时传且值不同返回 400。内部不要误将它解释成任务 owner。
- 对所有新的或改过的接口补齐注释：用途、权限、参数、响应、错误、版本、幂等。响应字段以移动端实际 `repository.dart`、模型、页面读取点为准，并同步拟定契约。

## 分步实施、逐步审查

DeepSeek 一次只交付一个阶段。每阶段完成后先停下，把变更文件、行为、测试增补、尚存问题和 `git diff --stat` 交给 Codex 审查；Codex 通过后再开始下一阶段。若审查未通过，只修当前阶段并重新提交审查，不顺手扩展范围。不要提交、推送或创建 PR。

仓库要求在实现期间不反复运行完整编译、静态分析或全套测试。因此“逐步验收”分为两层：阶段结束进行差异、层次、授权、数据语义和测试覆盖的代码审查；所有阶段结束后集中运行最终自动化和真实 PostgreSQL 链路。测试应随阶段编写，但完整测试只在最终验收阶段运行。只有最终验证有明确退出码后才能勾 OpenSpec 完成。

### 阶段 0：现状核对与差异修复清单

**动作：**

1. 运行并记录 `git status --short --branch`、HEAD 和 `git diff --stat`；完整阅读所有已改代码及 V22，不覆盖 `mobile/handoff.md` 的既存历史记录或未跟踪 `CLAUDE.md`。
2. 按本任务书逐项比较运行时代码、移动端序列化、当前 OpenAPI、需求规格和迁移；列出草案缺陷及准备改的文件。
3. 核对 `docs/mobile-openapi-contract.yaml` 的标记和实际 Controller，禁止将 PROPOSED 文档写成“已经实现”。
4. 对路线采用“扩展现有模块和端点 + `server` Flyway 向前迁移”；不另建并行 v2 资源/数据库，不在 Controller 中加 SQL，不从一个 Controller 调用另一个 Controller 复用业务。

**本阶段审查条件：** 基线和用户既存改动有记录；待修问题有文件路径；没有开始扩大范围；OpenSpec 严格校验通过。

### 阶段 1：数据库迁移和成员生命周期

**主要文件：** `server/src/main/resources/db/migration/V22__mobile_p0_contracts_and_direct_review.sql`（是否可改先核实未发布状态）、必要时后续 V 迁移、`OrganizationReviewedRevisionApplication.java`、迁移升级测试。

**动作：**

1. 新增结构化用户列和必要约束/索引；手机号列可 NULL 以支持清空，唯一约束继续有效。处理 JSONB 旧值时只有成功验证并转存的字段才能清理；非法/未知旧值必须保留或显式报告，不能静默丢数据。
2. 保留 `profile` 其余 JSONB 键；明确 JSONB 中旧 phone/email 等值与权威列冲突时的优先级，读取不能让旧 JSON 覆盖权威列。
3. 加入审核模式/决策来源及“步骤已替代”的可持久状态/审计方式；确保历史已决数据保留，历史待审候选不被应用。
4. `MEMBERSHIP` 待审事项分配唯一有效管理员步骤；其他类型仅按当前有效直属关系分配一个步骤；找不到 reviewer 时保持 request `PENDING` 且无可操作 step。迁移插入 outbox 必须有稳定去重键。
5. 在成员确认实际生效事务中，如果 `employment_start_date` 为空，写入上海当天；审批失败/回滚时不留下生效日期。
6. 新增升级测试：旧 JSONB 合法资料迁移、非法值不丢、phone 唯一和 NULL、已决/待审步骤处理、MEMBERSHIP 管理员分配、普通直属分配、无直属待审、重复迁移/幂等性。

**本阶段审查条件：** 迁移只在 `server` Flyway 路径；明确是否已发布；无历史候选生效；迁移数据前后有断言；回滚风险记录完整。

### 阶段 2：任务日历区间与接收卡片

**主要文件：** `module/task/TaskController.java`、`TaskQueryService.java`、必要的 `TaskListView`/参与人查询层；`TaskQueryServiceTest` 和任务 HTTP 集成测试；移动端 `data/repositories/repository.dart` 及其 HTTP 测试。

**接口：**

1. `GET /api/tasks?cursor&limit&search&from&to&participantId`，兼容 `ownerId` 作为参与人筛选别名；保留 `date/period` 老调用。客户端的月视图必须真正发送 `from/to`，不能把可见网格降成截止日期落月的 `date/period`。
2. 任务区间交集：有效任务区间满足 `start_at < to AND deadline >= from`；`start_at` 为 NULL 的旧记录按既有业务回退语义处理；`start_at > deadline` 的非法数据不应造成虚假命中。结果仍只用现有安全任务投影，不增加正文/完成情况字段。
3. `GET /api/tasks/received-card?cursor&limit&search` 返回 `{items,total,nextCursor}`；每项至少含 `id,title,version,phase,dispatchAt,participants,label` 以及移动端投影确实需要的时间字段。`dispatchAt` 使用最早真实 `DISPATCHED` 事件，缺失时为 null 并排在末尾；按 `dispatchAt DESC NULLS LAST,id` 稳定排序。返回全部当前有权查看的公司任务历史，包括撤回、验收、归档任务。
4. 校验成对范围、格式、`to > from`、冲突别名、无权 participant 和超长 search；错误不能扩大结果范围。

**验收案例：** 同一参与人任务覆盖范围前/中/后端；跨月相交任务返回；刚好 `deadline == from` 命中、`start_at == to` 不命中；空 startAt 可见；非法区间不命中；参数冲突 400；越权成员拒绝；卡片包含各种终态；派发事件缺失置后；相同事件时间按 ID 稳定；分页无重复/漏页；Flutter HTTP 断言请求真的含 `from/to`。

### 阶段 3：下属日志列表和月状态日历

**主要文件：** `module/log/controller/LogController.java`、`application/LogQueryService.java`、`application/LogQueryRepository.java`、`Business.java`；`LogQueryServiceTest`、下属日志 HTTP/数据库集成测试、Flutter HTTP 测试。

**接口：**

1. `GET /api/logs/subordinates?cursor&limit&ownerId&departmentId&search&from&to`：仅返回已提交日志；参数必须组合过滤。`ownerId` 必须是当前用户实时组织关系下的在职下属（含产品定义允许的递归祖先查询范围）；普通 `/api/logs` 本人草稿行为不变。
2. `GET /api/logs/subordinates/calendar?ownerId=<id>&month=YYYY-MM` 返回：
   ```json
   {"ownerId":"u1","month":"2026-10","employmentStartDate":null,
    "days":{"1":"UNKNOWN","2":"SUBMITTED","3":"MISSING","31":"FUTURE"}}
   ```
   `days` 覆盖该月所有自然日，键为不补零的日号字符串；响应应包括已确认的日志 ID，若移动端模型/调用确需该字段则统一更新模型和 YAML。无可信入职日的未提交过去日期为 `UNKNOWN`；未来为 `FUTURE`；提交事实为 `SUBMITTED`；仅明确已入职且已到期未交才是 `MISSING`。
3. 用实际 `reporting_relations` 递归关系和当前 ACTIVE 状态授权；同级、越公司、离职员工和调岗后旧上级不能读取。详情读取必须与列表/月历的成员范围一致，不能出现“日历能点、详情 403”的权限不一致。
4. 将移动端下属列表 `Query.from/to` 序列化为这两个参数；本人日志日期查询仍按已有契约，不要无理由更改。

**验收案例：** 31/30/闰年月份完整日期数；上海午夜边界；提交/缺交/未来/未知入职状态；部门+搜索+成员+范围共同生效；跨范围/非下属/失权 403；无草稿泄漏；详情可读范围与日历一致；客户端发出 from/to 并解析所有状态。

### 阶段 4：已提交日志直接修改正文

**主要文件：** `LogController.java`、`LogWorkflowService.java`、`LogEditWindow.java`、`LogQueryRepository/Service` 以及历史修订应用服务；`LogWorkflowServiceTest`、日志 HTTP 集成测试、Flutter HTTP 测试。

**接口：** `PUT /api/logs/{id}/content`，请求 `{ "work": "非空正文", "version": 4 }`，成功返回带新 `version`、原 `submittedAt`、`editableUntil`、`canEdit` 的日志视图。

**动作与规则：**

1. 首次提交日志的业务日期只能是上海今天、昨天或前天；这是提交规则，不限制之后的编辑时间。
2. 修改只允许日志作者本人、当前 ACTIVE、已提交且当前版本一致；`now < submitted_at + 24h` 才允许，恰好 24 小时及之后拒绝。窗口由首次 submitted_at 计算，编辑不能重置它。
3. 同一事务执行锁、授权、版本/状态/窗口校验、只替换 `work`、写 `log_versions`/审计、递增 version；保留历史正文其他字段、`business_date` 和 submitted_at。
4. 正确处理锁顺序，避免与 review/log 路径死锁；不要让旧 revisions、withdraw 或 apply 历史候选绕过窗口或覆盖新正文。旧待审候选应被显式 supersede/终止并留审计。
5. 稳定错误至少区分 `VERSION_CONFLICT`、`LOG_EDIT_WINDOW_EXPIRED`、`LOG_NOT_EDITABLE`、空正文校验及无权访问；隐藏按钮不代替服务端拒绝。

**验收案例：** 首交当日/前两日通过，超过三日首次提交拒绝；刚提交和 23:59:59 通过；24:00:00 拒绝；版本冲突 409；并发仅一次成功；他人、草稿、撤回态拒绝；正文以外字段和 submitted_at 未变；旧 pending revision 不可覆盖；失败事务无部分历史记录。

### 阶段 5：个人资料 GET/PUT 与字段映射

**主要文件：** 把目前 `DashboardController` 中资料 SQL/业务规则提取至 dashboard/profile 应用服务与 Repository（按现有模块风格建类），Controller 仅解析请求；`OpenApi.java`、profile 服务测试、`BackendIntegrationTest`、Flutter `repository.dart` 及 HTTP 测试。

**接口：**

1. `GET /api/profiles/{id}` 对本人、真实组织祖先及产品已有合法组织管理员返回允许字段：`id/name/version/position/role/status/phone/email/gender/age/employmentStartDate/department/profile`。对平级或无关高职级用户拒绝。公开登录 `/auth/me` 不因此泄露联系方式。
2. `PUT /api/profiles/me` 使用 `version`，只接受 `introduction/phone/email/gender/age/avatarAttachmentId/version`。缺席字段保持原值；明确 null/空值按已确认的选填可清空处理。拒绝姓名、部门、职位、角色、状态等未知/只读字段。
3. phone 写 `users.phone` 并依赖唯一索引；重复号码在并发下也返回 409 稳定错误。简介/头像更新时 merge JSONB，不清除其他 profile 键；avatar 需再次校验当前用户附件归属。年龄只做整数非负检查，不加任意上限；gender 自由文本 ≤32，email 校验格式和长度。
4. 响应中的结构化顶层值是权威值；Flutter `_record` 不得用过期 `profile.phone/email/gender/age` 覆盖它们。保留组织字段只读展示和已有 UI 模型需要的字段映射。

**验收案例：** 正常读写/空值清空/版本冲突/重复手机号与并发唯一约束/非法邮箱年龄性别/尝试写组织字段/他人附件/JSONB 其他键保留/旧 profile 值冲突/调岗后旧上级失权。确认注册流程仍按现行规则创建待管理员确认员工。

### 阶段 6：#17 直属单级审核与历史待审迁移

**主要文件：** `ReviewController.java`、`ReviewApi.java`、`DefaultReviewApi.java`、`ReviewApplicationService.java`、`ReviewRepository.java`、所有 `ReviewedRevisionApplication` 处理器、组织策略服务与审核测试。

**接口和规则：**

1. 决定请求必须是 `{approve,reason?,expectedVersion}`；接口、`ReviewApi`、adapter、service 和测试全部一致传递 expectedVersion，禁止用当前版本静默代替请求版本。
2. 新普通关键变更 request 使用 `DIRECT_MANAGER` 并只建一个当前直属审核 step；`MEMBERSHIP` 使用 `ADMIN_MEMBERSHIP`，只给当前有效的非申请人管理员审核。缺少有效审核人时 request 保持 PENDING，待组织关系补齐后由申请人现有 reroute 路径重新分配。
3. 决定事务内刷新 Actor、锁 request/step/target、验证当前审核关系仍有效、申请人非 reviewer、expectedVersion 与目标一致、审批权限和驳回原因；审批应用、状态、审计、step 与 outbox 同事务。
4. Founder exemption 在创建新申请时必须重新查询当前角色和业务权限，不能信任旧 Actor 快照；只对已有权限的非 MEMBERSHIP 请求生效。同步写申请 APPROVED、`decision_source=FOUNDER_EXEMPT` 与审计/outbox；不生成可执行待审 step。管理员不得因其管理员身份获得创始人例外。
5. 迁移/重路由保留旧决策历史，所有旧 pending 步骤标记替代；历史 pending candidates 绝不调用 apply handler。检查有先前 APPROVED 历史 step 的仍 PENDING 请求是否能安全 reroute；若不能，修复 service 状态判定，不能让迁移制造永远无法完成的申请。
6. detail/list 的当前 reviewer、configured、申请人和步骤投影不能只依赖旧关系快照；失效 reviewer 不能继续读/决定超出当前授权的资料。修复 Repository 的 SQL alias/计数及其他可执行查询错误。
7. 旧多级策略写入明确拒绝或清理；不能留存让其他客户端误以为仍启用的可执行策略。更新服务端/移动端策略投影和 JavaDoc。

**验收案例：** 普通直属审核通过/驳回；自审拒绝；空驳回理由拒绝；旧 expectedVersion 409；关系撤销后旧审核人拒绝；无上级待审+关系补齐 reroute；Founder 权限内免审与越权不免审；非 founder admin 不免审；MEMBERSHIP 仍仅 admin approve，founder member 仍待管理员；旧 pending 不应用；历史已决留存；审计/outbox 同事务；重复决定不重复应用。

### 阶段 7：统计授权查询、汇总和图表钻取

**主要文件：** 重构 `module/analytics/controller/AnalyticsController.java`；实现 analytics application/query repository/DTO；复用统一 filters/range/authorization；维护 `AnalyticsApi` 如确有公共调用者；新增 analytics 单测和 HTTP/数据库集成测试。

**实现要求：**

1. Controller 不含 SQL，不调用 `TaskController`/`LogController`；timeline 如需共用查询，调用应用服务/Repository。
2. 汇总和详情共同解析 `date/period/groupBy/departmentId/teamId/ownerId`。`groupBy` 只允许 department/team/person；筛选对象不存在/格式错返回 400，超出当前 actor 范围返回 403，不得忽略筛选器。
3. `GET /api/analytics` 返回移动端模型读取的 `range,updatedAt,filters,groupBy,dispatched,received,feedback,accepted,overdue,onTimeAcceptance,dailySubmission,groupedComparison,taskPhaseDistribution,trend`；如保留兼容字段，值必须由同一查询得到。Metric 包含 numerator、denominator、definition；denominator=0 时 rate 为 null（JSON 必须允许 null），不能返回 0 冒充有效比例。
4. 分组比较每行至少含 `groupId/groupName` 和 dispatched/received/feedback/accepted/overdue/diarySubmitted 等图表数据；趋势覆盖区间内每个上海自然日，按真实事件时间聚合；阶段分布仅展示数据能够证实的阶段。
5. 事件来源逐项核对 `task_events` 的真实事件类型和序号语义：派发/接收/反馈/验收按各自事件时间聚合；改期后按当前有效任务版本规则计算准时验收；日志按已提交事实和 business_date 计数。没有历史事件的数据不能从当前 phase 倒造收到/反馈/验收历史。删除或停止使用依赖已停用日志阅读登记的 `unreadLogs`。
6. `GET /api/analytics/details` 参数沿用相同日期/过滤器，另需 `metric`、可选 `groupId`、`bucket=YYYY-MM-DD`、`cursor/limit`。metric 白名单：`dispatched,received,feedback,accepted,overdue,diarySubmitted,onTimeAcceptance` 和系统实际支持的 `phase:<phase>`；非法 metric/bucket/group 400。按详情同样的数据范围返回稳定分页的真实任务/日志记录，不泄露草稿/私人数据。

**验收案例：** 三种 groupBy；部门/团队/人员过滤交叉；全局管理员/普通成员/直属上级；非法与无权 filter；零分母为 null；每个已支持 metric 的计数与手工 SQL fixture 对上；事件日跨 UTC/上海午夜；无事件历史不伪造；phase 标签只返回实际状态；同 group/bucket 的分页稳定；详情总数等于汇总相应分组计数。

### 阶段 8：同范围 CSV 导出

**主要文件：** Analytics application/repository 与 controller、导出测试、移动端导出调用/筛选状态模型和 HTTP 测试。

**接口：** `GET /api/analytics/export?date&period&resource&groupBy&departmentId&teamId&ownerId`；resource 只允许 logs/tasks；使用阶段 7 的同一 Filters、Range、Authorization 和 SQL 过滤对象，不复制一份相似但可能偏离的过滤 SQL。CSV UTF-8（按既有客户端需要 BOM）、稳定列/排序、公式注入转义；最多 10000 条，超过时明确 400/409 错误且不返回截断数据冒充全量。CSV 只导出当前 Actor 有权看的字段，不含日志草稿、手机号、私人备注或不必要敏感字段。

**验收案例：** 对同一筛选分别比较汇总/明细/CSV ID 与数量；部门/团队/人员筛选一致；CSV 公式前缀 `=,+,-,@,tab,CR` 安全；引号/逗号/中文行正确编码；10000 条边界和超限；无权筛选报错；移动端传递当前画面同一套 filter。

### 阶段 9：移动端适配、运行时 OpenAPI 和文档同步

**主要文件：** `mobile/lib/data/repositories/repository.dart`、必要的 `models.dart`/profile mapping 和 Flutter HTTP tests；`server/src/main/java/cn/workpanel/OpenApi.java`；`docs/openapi.json`（按项目生成，不手工拼写）；`docs/mobile-openapi-contract.yaml`、`docs/backend-interface.md`、详细 gap 文档、OpenSpec proposal/design/spec/tasks/verification、local Issue、handoff。

**动作：**

1. 基于已实现端点逐个核对实际网络 method/path/query/body/response mapping。确认任务和下属日志范围确实发出 from/to；member month model接受 employmentStartDate/days/UNKNOWN；日志编辑发 work/version；review decision 发 expectedVersion；profile decoder使用列优先；analytics queries/export共享完全相同筛选。
2. 将所有接口的字段 required/nullable、约束、权限、分页、冲突码、版本、幂等、时间时区写进运行时 SpringDoc 和 PROPOSED 移动端契约。PROPOSED 只有在运行时实现后才可标为已实现；不得把草案复制为快照。
3. 核对 `BackendIntegrationTest` 生成/写入 `docs/openapi.json` 的真实机制，用项目测试或导出流程生成快照，再检查 diff。同步接口缺口文档状态和交接记录；只写实际已验证证据。

**审查条件：** Flutter HTTP 测试断言序列化，不仅检查 mock repository；生成快照与 Controller 一致；接口、设计、迁移和错误语义互相一致；P1 未被误报为完成。

### 阶段 10：统一最终验收与交付记录

只有阶段 0–9 都经 Codex 阶段审查后，集中执行：

1. `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`；环境资源不足时按脚本支持使用 `-DockerMaven`。需要有真实 PostgreSQL 的 Flyway 升级和 HTTP 集成证据。
2. 受影响 Flutter HTTP/model tests、`D:\flutter\bin\flutter.bat analyze --no-pub`；按仓库条件运行完整 `flutter test --no-pub`，与 2026-10-24 历史 267/31/2 结果分开报告。
3. `openspec.cmd validate --all --strict`、`git diff --check`、OpenAPI 快照差异核对。
4. 正向、异常、权限、并发和历史迁移用例齐全；验证至少两项非功能要求（建议组织隐私/越权隔离、审核与编辑事务可靠性）；保留命令、环境、明确退出码、测试统计和限制。
5. 更新 `verification.md`、OpenSpec 状态表和 `mobile/handoff.md`。只勾选有实际通过证据的任务。前端设备/UI #1–#16 等既存未验收项仍标为未验证。
6. 输出交给 Codex 的审查包：功能摘要、逐文件变更、迁移及兼容影响、验证证据、失败/未验证项、风险、`git diff --stat`。此阶段仍不提交/推送/创建 PR。

## 目前已知必须先修的草案问题

- 当前 `repository.dart` 的 `_query()` 仍把日期范围转成 `date/period`，没有按 P0 任务/下属月历请求真正发送 `from/to`。
- Analytics 运行时 `/analytics/details` 尚未实现，现有 `AnalyticsController` 内有 SQL 并直接调用其他 Controller；需要按阶段 7 重构。
- Profile 新 SQL 目前写在 `DashboardController`，需要按阶段 5 下沉；Flutter `_record()` 中旧 JSON profile 字段可能覆盖列值。
- `ReviewApi`/`DefaultReviewApi` 是否已全链路传递 `expectedVersion` 仍不一致；修复 interface、adapter、service、controller 和所有调用点。审核 list count 查询别名需复核。
- 日志日历/列表/详情授权需要统一到实时 reporting ancestor 范围；不能只在 calendar/list 放宽，detail 仍按旧角色范围拒绝，也不能把全公司用户开放给普通 manager。
- V22 对 legacy JSONB 的清理和 phone nullability 必须通过数据保留测试；未转存的旧值不得删除。phone 可空依据需求审计里“选填值可清空”，保持唯一索引。
- Founder exemption 必须 fresh-load actor；历史有已批准步骤但 request 仍 pending 的 reroute 路径必须有可完成语义。
- 现有旧测试如果与确认规则冲突，要按新产品要求更新断言/夹具，不能删弱测试以求通过。
