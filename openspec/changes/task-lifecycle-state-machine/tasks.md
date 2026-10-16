## 1. 数据迁移

- [ ] 1.1 新增 `server/src/main/resources/db/migration/V6__task_lifecycle.sql`：`task_events` 增加 `from_phase`、`to_phase`、`task_version`，扩展事件类型约束（含 `RETURNED`、`REASSIGNED`、`RESCHEDULED`）；在含 V1–V5 数据的库上启动，验证 Flyway 成功且历史事件行未被修改
- [ ] 1.2 新增 `server/src/main/resources/db/migration/V12__task_revision_review_kinds.sql`：以前向方式扩展 `review_requests_kind_valid`，允许 `TASK_REASSIGN` 与 `TASK_RESCHEDULE`；在含 V1–V11 数据的库上启动，验证 Flyway 成功且既有复核记录不变

## 2. 状态机

- [ ] 2.1 实现 `module/task/TaskStateMachine`（状态、动作、角色枚举与转换表）；编写 `TaskStateMachineTest` 穷举 6 状态 × 8 动作 × 5 角色，断言与 spec 表格一致并通过
- [ ] 2.2 实现角色计算（主负责人、协作人、派发人、管理员可叠加）；单元测试覆盖一人多角色与仅凭组织范围可读的上级

## 3. 生命周期动作

- [ ] 3.1 实现 `TaskLifecycleService`：锁行 → 格式 → 角色 → 版本 → 状态 → 更新并追加带前后状态与版本的事件、审计、既有 outbox 写入；编写 `TaskLifecycleServiceTest` 验证判定顺序（旧版本 + 错误状态返回 `VERSION_CONFLICT`）及失败时不写事件
- [ ] 3.2 实现 `TaskLifecycleController`（`POST /api/tasks/{id}/events`，支持 `RECEIVED/FEEDBACK/ACCEPTED/RETURNED/ARCHIVED/WITHDRAWN`，说明必填规则），从 `Tasks.java` 移除旧端点；验证应用启动无重复映射

## 4. 转派与改期

- [ ] 4.1 实现 `POST /api/tasks/{id}/reassignments`、`POST /api/tasks/{id}/reschedules` 的申请校验（非终态、派发人/管理员、新负责人有效且不同、带时区新截止时间且不同），调用现有 `Reviews.create` 创建 `TASK_REASSIGN`/`TASK_RESCHEDULE` 申请；单元测试覆盖各拒绝分支
- [ ] 4.2 实现 `TaskRevisionService.apply`：转派替换参与人并回到 `DISPATCHED`、改期保持状态、通用修订拒绝改负责人/截止时间且保持状态；`Reviews` 仅新增 kind 白名单与分派委托；编写 `TaskRevisionServiceTest` 并通过
- [ ] 4.3 统计并记录 `review_requests` 中待审 `TASK` 修订是否含负责人或截止时间变化，结果写入上线说明

## 5. 契约

- [ ] 5.1 更新 OpenAPI：事件动作枚举、转派/改期接口、`INVALID_TRANSITION`、`SAME_OWNER`、`USE_DEDICATED_REVISION`；访问 `/api/openapi` 验证出现

## 6. 集成测试

- [ ] 6.1 扩展既有 `server/src/test/java/cn/workpanel/module/task/TaskDispatchIntegrationTest`：正常生命周期、验收退回后再反馈、协作人多次反馈，断言时间线顺序、前后状态与版本递增
- [ ] 6.2 非法转换：未接收先反馈、未反馈先验收、撤回已验收、终态后任意动作/转派/改期均返回 409 `INVALID_TRANSITION` 且时间线不变；未知动作、缺说明返回 400
- [ ] 6.3 越权：协作人接收、负责人验收、仅凭组织范围的上级验收返回 403；范围外用户动作与读取返回 404
- [ ] 6.4 版本冲突：旧版本提交返回 409 `VERSION_CONFLICT` 且无事件；2 线程同版本并发动作恰好一个成功；缺少或非法版本返回 400
- [ ] 6.5 转派与改期：转派复核通过后新负责人可接收、原负责人 404、状态 `DISPATCHED`；复核中不生效；复核期间版本变化导致生效 409；改期后状态保持并出现 `RESCHEDULED`；非法申请不创建复核
- [ ] 6.6 回滚：模拟事件写入失败，断言任务状态与版本未变

## 7. 交付校验

- [ ] 7.1 在 `server` 目录运行 `mvn -q test`，含 `BackendIntegrationTest` 在内全部通过
- [x] 7.2 在仓库根目录运行 `openspec.cmd validate --all --strict`，本变更通过（2026-10-14：11 项通过）
