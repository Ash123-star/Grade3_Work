## Why

任务派发是任务与日报后端的起点，后续生命周期、列表、日志关联都依赖“一次派发只产生一个任务、参与人与附件归属可信、事件可追溯”。现有实现集中在扁平包 `cn.workpanel.Tasks`/`Business` 中，幂等摘要对协作人顺序敏感、附件校验与绑定规则相互矛盾、事件时间线缺少只追加约束，且缺少针对派发的单元测试。需要先把派发迁入 `module/task` 并固化契约，后续 4 个变更才能在其上叠加。

## What Changes

- 新建 `server/src/main/java/cn/workpanel/module/task`，承载任务派发、任务详情读取与事件时间线；`POST /api/tasks`、`GET /api/tasks/{id}` 路径与请求/响应结构保持兼容。
- 幂等键：按“派发人 + 幂等键”唯一；请求体规范化（协作人、附件去重排序，主负责人从协作人中剔除，补默认紧急度）后计算摘要；相同摘要重放返回同一任务，摘要不同返回 409 `IDEMPOTENCY_CONFLICT`；并发重放串行化，只创建一个任务。
- 负责人与协作人：恰好一名主负责人，协作人去重且不含主负责人；全部必须为本公司在职且在派发人可见范围内的用户。
- 附件引用：只能引用派发人本人上传且尚未绑定其他任务的附件；已绑定其他任务返回 409 `ATTACHMENT_BOUND`；派发成功后附件绑定到该任务。
- 事件时间线：派发写入首条 `DISPATCHED` 事件；事件只追加、按序号有序，数据库层禁止修改与删除；任务详情返回时间线。
- 初始状态：新任务固定为 `DISPATCHED`、版本 1；请求中携带 `phase`、`version`、完成情况等服务端字段时拒绝。
- 越权读取：不在任务数据范围内（非派发人、非参与人、非组织上级）读取任务详情或时间线返回 404，不泄露任务存在性。
- 新增 Flyway 迁移 `V4__task_dispatch.sql`，以及 `module/task` 的单元测试与真实 PostgreSQL/Redis 集成测试。
- 明确不实现：组织审核链、通知投递（仅保留现有 outbox 写入，不改投递）、AI provider、Flutter 接口调用。接收/反馈/验收/转派/改期/撤回/归档等状态流转属于变更 2；任务列表属于变更 3。

## Capabilities

### New Capabilities
- `task-dispatch`: 任务派发、幂等重放、负责人与协作人、附件引用、事件时间线、初始状态与任务详情读取范围。

### Modified Capabilities
（无。`collaboration-backend` 中 “Task dispatch and lifecycle” 的总体要求不变，本变更在新能力中细化派发部分。）

## Impact

- 代码：新增 `cn.workpanel.module.task` 包；`Tasks.java` 移除派发与详情端点，保留列表、事件、修订端点直至变更 2/3；`Business.validateTask/assign/taskDto` 改为委托新模块；`AiApi.confirm` 与 `Reviews` 改为调用新派发服务/参与人组件。
- 可见性：`Actor`、`Db`、`ApiError` 中被新包使用的成员需由包私有改为 `public`，行为不变。
- 数据库：新增迁移 V4（幂等记录补充创建时间与规范化摘要、附件绑定索引、事件类型约束、事件只追加触发器）。V5 起留给后续变更。
- API：`POST /api/tasks` 新增错误码 `IDEMPOTENCY_CONFLICT`（已存在）、`ATTACHMENT_BOUND`、`SERVER_MANAGED_FIELD`；成功与重放响应结构不变。Web 与 Flutter 共享同一 OpenAPI `TaskDraft` 契约。
- 测试：新增 `server/src/test/java/cn/workpanel/module/task/` 下单元测试与集成测试；现有 `BackendIntegrationTest` 需保持通过。
