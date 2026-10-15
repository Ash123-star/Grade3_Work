## Context

现有 `Tasks.event` 用 `switch` 同时判断角色和状态，任一不满足都抛 403；版本检查在 `UPDATE ... WHERE version=?` 时进行，但角色/状态检查在之前，所以过期请求可能先收到 403。`Reviews` 的 `TASK` 生效分支整体替换任务内容并强制 `phase='DISPATCHED'`。依赖变更 1 已在 `module/task` 提供 `TaskAccess`、`TaskTimeline`、`TaskParticipants`、`TaskAttachments`，并以 V4 为事件表加了只追加触发器和类型约束。

## Goals / Non-Goals

**Goals:**
- 显式、可单测的转换表，状态错误与权限错误分开。
- 转派、改期有专门接口和事件，改期不丢进度。
- 统一的版本校验顺序与 409 语义。

**Non-Goals:**
- 修改复核层级、路由、策略或禁止自审规则（组织审核链）。
- 通知投递改造；只保留现有 outbox 写入。
- 任务列表（变更 3）、日报（变更 4、5）、AI provider、Flutter 接口调用。
- 子任务、批量操作。

## Decisions

### 1. 转换表
`TaskStateMachine` 为纯函数：`Transition decide(Phase current, Action action, Role role)`，`Role ∈ {OWNER, COLLABORATOR, ISSUER, ADMIN, OTHER}`（由 `TaskAccess` 计算，一人可多角色，取允许集合并集）。结果为 `Allowed(next)`、`Forbidden`、`InvalidTransition`。表数据以 `EnumMap` 定义，与 spec 表格一一对应，单元测试对 6 状态 × 8 动作 × 5 角色做穷举断言。
备选：数据库存转换表。放弃原因：规则少且需要编译期检查。

### 2. 判定顺序
`读取范围(404) → 请求格式(400) → 角色(403) → 版本(409 VERSION_CONFLICT) → 状态(409 INVALID_TRANSITION)`。实现：`SELECT ... FOR UPDATE` 锁行后，在内存中比较 `version`，再判定状态，最后 `UPDATE ... WHERE id=? AND version=?` 作为二次保护。版本先于状态判定，保证持旧版本的客户端总是被提示刷新，而不是看到误导性的状态错误。

### 3. 转派、改期走候选修订
新接口 `POST /api/tasks/{id}/reassignments {ownerId, version, reason}`、`POST /api/tasks/{id}/reschedules {deadline, version, reason}`：校验后调用现有 `Reviews.create(actor, kind, ...)`，`kind` 分别为 `TASK_REASSIGN`、`TASK_RESCHEDULE`；`candidate` 只含变化字段。`Reviews.apply` 对这两种 kind 及原 `TASK` 委托 `TaskRevisionService.apply(kind, ...)`。复核链计算沿用 `TASK` 的规则，不修改 `Reviews` 中的路由与策略代码，只在 kind 白名单和分派处增加两个分支。
- 转派生效：锁任务 → 比较 `expected_version` → 状态非终态 → 新负责人仍有效 → 更新 `owner_id`、`task_assignees`（删除旧 PRIMARY、删除新负责人的 COLLABORATOR 行、插入新 PRIMARY）→ `phase='DISPATCHED'` → 事件 `REASSIGNED {fromOwnerId,toOwnerId,reason}`。
- 改期生效：更新 `deadline` 与 `body.deadline`，保持 `phase`，事件 `RESCHEDULED {fromDeadline,toDeadline,reason}`。
- 原 `TASK` 通用修订：保持现行为（内容替换），但不再改 `owner_id`/`deadline`——这两项必须走专门接口；通用修订候选中 `ownerId`、`deadline` 与当前值不同时返回 400 `USE_DEDICATED_REVISION`。通用修订生效时保持当前状态，不再强制回到 `DISPATCHED`。

### 4. 事件结构
V6 为 `task_events` 增加 `from_phase text`、`to_phase text`、`task_version int`（历史行为空）。事件类型约束扩展为 `DISPATCHED, RECEIVED, FEEDBACK, ACCEPTED, RETURNED, ARCHIVED, WITHDRAWN, REVISED, REASSIGNED, RESCHEDULED`；为兼容 V5 已可能写入的历史事件，`TRANSFERRED` 保留为仅历史兼容类型，新状态机不再产生它。V5 的只追加触发器保持不变；V6 通过 `ALTER TABLE ... ADD COLUMN` 加列不受触发器影响。

### 5. 错误码
`INVALID_TRANSITION`（409，新）、`VERSION_CONFLICT`（409，现有）、`SAME_OWNER`（400）、`USE_DEDICATED_REVISION`（400）、`INVALID_EVENT`（400，现有）。OpenAPI 同步更新，Web 与 Flutter 共用。

### 6. 测试策略
- 单元：`TaskStateMachineTest` 穷举；`TaskLifecycleServiceTest` 用 Mockito 验证判定顺序（过期版本 + 错误状态时返回 VERSION_CONFLICT）与失败时不写事件；`TaskRevisionServiceTest` 验证转派参与人替换、改期保持状态。
- 集成：`TaskLifecycleIntegrationTest`（真实 PostgreSQL/Redis）覆盖 spec 全部场景，并发场景用 2 线程同版本提交。
- 现有 `BackendIntegrationTest` 中依赖 403 状态错误的断言如有，随本变更改为 409。

## Risks / Trade-offs

- [错误码从 403 改为 409 影响客户端] → 当前 Web/Flutter 尚未接入（Flutter 接口调用不在范围），在 OpenAPI 中标注；风险低。
- [通用修订不再允许改负责人/截止时间] → 已存在的待审 `TASK` 修订若包含这类变化，生效时会被 400 拒绝；迁移前统计 `review_requests` 中 `kind='TASK' AND status='PENDING'` 的数量，若非 0 在上线说明中告知需重新提交。
- [转派后原负责人立即失去访问] → 符合“一名主负责人”约束；原负责人的历史反馈仍保留在时间线，派发人可见。

## Migration Plan

1. V6 只加列与替换约束，可在线执行；替换约束前确认无历史行违反新约束（新约束是旧约束的超集）。
2. 回滚：旧代码不读取新列，新事件类型 `RETURNED/REASSIGNED/RESCHEDULED` 旧代码按普通事件展示；不提供向下迁移。

## Open Questions

（无。退回动作、改期保持状态、通用修订限制均已在上文决定，确认时可调整。）
