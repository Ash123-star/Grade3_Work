## Why

派发之后，任务要经过接收、反馈、验收、归档，中途还会转派、改期或撤回。现有 `Tasks.event` 用 `switch` 内联状态规则：错误状态与无权限都返回 403，无法区分；没有转派、改期的专门流转，只能走通用修订，且修订生效时无条件把状态重置为 `DISPATCHED`，改期会丢失进度；验收只能通过，不能退回。需要在 `module/task` 中建立显式状态机和统一的版本并发控制。本变更依赖变更 1 `task-dispatch-idempotency`。

## What Changes

- 在 `server/src/main/java/cn/workpanel/module/task` 新增状态机：状态 `DISPATCHED`、`RECEIVED`、`FEEDBACK`、`ACCEPTED`、`ARCHIVED`、`WITHDRAWN`，以转换表定义“谁、在什么状态、执行什么动作、进入什么状态”。
- 动作：接收（主负责人）、反馈（主负责人或协作人，可多次）、验收通过 / 验收退回（派发人或管理员，退回需原因，回到 `RECEIVED`）、归档（派发人，仅验收后）、撤回（派发人，终态前，需原因）。
- 转派（更换主负责人）、改期（修改截止时间）作为关键变更，沿用现有候选修订与独立复核流程提交，生效时写入 `REASSIGNED` / `RESCHEDULED` 事件；转派后状态回到 `DISPATCHED`，改期保持原状态。
- 版本并发控制：所有动作与候选修订必须携带 `version`，与当前版本不一致返回 409 `VERSION_CONFLICT`，不产生任何写入；成功后版本加 1。
- 错误语义统一：范围外 404，角色不符 403，版本过期 409 `VERSION_CONFLICT`，当前状态不允许该动作 409 `INVALID_TRANSITION`。
- 事件时间线记录前后状态与生效版本。
- 新增 Flyway 迁移 `V6__task_lifecycle.sql`；并通过前向迁移 `V12__task_revision_review_kinds.sql` 扩展既有复核申请类型约束，以允许 `TASK_REASSIGN` 与 `TASK_RESCHEDULE`，以及单元测试与集成测试。
- 明确不实现：组织审核链本身（只调用现有复核接口，不改复核路由、层级、策略）、通知投递（保留现有 outbox 写入）、AI provider、Flutter 接口调用。

## Capabilities

### New Capabilities
- `task-lifecycle`: 任务状态机、接收/反馈/验收/归档/撤回动作、转派与改期、版本并发控制及错误语义。

### Modified Capabilities
（无。`collaboration-backend` 的“关键变更审核后生效”保持不变，本变更沿用。）

## Impact

- 代码：新增 `module/task` 下 `TaskStateMachine`、`TaskLifecycleService`、`TaskLifecycleController`、`TaskRevisionService`；`Tasks.java` 移除 `event`、`revision` 端点；`Reviews` 中 `TASK` 生效分支改为委托 `TaskRevisionService`（复核流程本身不变）。
- API：`POST /api/tasks/{id}/events` 新增动作 `RETURNED`；新增 `POST /api/tasks/{id}/reassignments`、`POST /api/tasks/{id}/reschedules`（返回复核申请）；原 `POST /api/tasks/{id}/revisions` 保留用于其他内容修订。错误码 `INVALID_TRANSITION` 替代原状态错误时的 403，属于客户端可见变化（**BREAKING** 仅错误码）。
- 数据库：V6 为 `task_events` 增加 `from_phase`、`to_phase`、`task_version`（历史行可空），扩展事件类型约束；V12 扩展 `review_requests.kind` 约束，不修改既有复核记录。
- 依赖：变更 1 的 `TaskTimeline`、`TaskAccess`、`TaskParticipants`。
