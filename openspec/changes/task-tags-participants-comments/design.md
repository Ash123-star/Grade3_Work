## Context

任务模块当前把 `tasks.owner_id` 作为主负责人，并以 `task_assignees.kind` 区分 `PRIMARY`/`COLLABORATOR`；任务创建直接写入 `tasks`，通用修订和转派/改期才走复核。该实现既无法表达无角色参与人集合，也不能满足创建、修改和删除必须审核的要求。`review_requests` 已支持候选值、申请/审核记录、禁止自审和事务内调用业务生效器，适合承载任务治理，但其种类约束和任务业务生效器需以前向迁移扩展。

## Goals / Non-Goals

**Goals:**

- 正式任务只在创建审核批准后落库；修改与删除均通过现有审核机制生效。
- 使用一个去重参与人集合，详情与列表不暴露主负责人、协作人或独立完成情况字段。
- 以 PostgreSQL `timestamptz` 持久化开始/截止时间，保留客户端提交的带时区 ISO-8601 值。
- 保证单标签、标签范围、评论读写范围、审计、乐观锁和事务通知可验证。

**Non-Goals:**

- 不重写组织审核路由、审核层级、通知投递器或 SSE。
- 不实现 Flutter、Android、Web 角色入口、AI provider。
- 不删除旧任务列或已发布迁移；旧列仅作为兼容数据来源。

## Decisions

### 1. 参与人集合为规范模型

新增 `task_participants(task_id, user_id, company_id, created_at)`，主键为 `(task_id,user_id)`，不含角色列。`V20` 从 `tasks.owner_id` 与 `task_assignees` 回填，并以唯一主键消除重复。新写入只写 `task_participants`；旧的 `owner_id`、`task_assignees` 不再对外返回，也不再决定新任务权限。

详情与列表通过 `TaskParticipants.list` 返回 `participants`（含用户 ID、昵称、头像标识），任务可读范围为派发人、参与人或满足既有组织范围的人员。旧任务若因迁移异常缺少参与人，读取时以 `owner_id`/`task_assignees` 联合去重作为后备，确保兼容读取。

备选方案是继续保留 `PRIMARY/COLLABORATOR` 并仅隐藏字段。拒绝：业务规则仍会依赖已废弃角色，无法保证“参与人以集合为准”。

### 2. 审核前候选、审核后生效

新增 `TASK_CREATE`、`TASK_DELETE` 审核种类，并保留 `TASK` 作为任务修改种类。创建接口校验草稿、参与人、标签与附件后，将规范化候选写进 `review_requests`；`target_id` 预分配为未来任务 ID，审核通过时才插入 `tasks`、参与人、标签、附件和时间线。幂等记录保存预分配 task ID 与 review ID，重复同键同内容返回同一申请；相同键不同内容返回 `409 IDEMPOTENCY_CONFLICT`。由于待审阶段不存在正式 `tasks` 行，前向迁移会移除 `idempotency_keys.task_id` 的旧外键；待审记录以 `review_id` 作为实际关联，批准后 `task_id` 仍指向新建任务。

修改接口继续使用 `TASK`，但候选采用新任务草稿，审核通过后在 `UPDATE ... WHERE version=?` 中生效。删除接口创建 `TASK_DELETE` 候选，其中保存理由和原任务摘要；批准时以乐观锁将任务归档、追加 `ARCHIVED` 时间线事件、写审计记录，绝不执行 `DELETE FROM tasks`。审核拒绝只改变申请状态，任务保持原状态。

既有 `TASK_REASSIGN`/`TASK_RESCHEDULE` 仅为已存在审核申请的历史兼容分支，不在新契约中创建主负责人语义。新的参与人/时间变更通过 `TASK` 修改申请。

### 3. 标签与时间

`task_labels` 包含 ID、名称、分类、颜色、公司、可选部门、创建人、状态、版本、创建/更新时间；名称在同一公司和部门范围内唯一。`task_label_links` 以 `task_id` 为主键，保证每个任务最多一个标签。选择标签时服务端要求标签 `ACTIVE`、同公司且部门范围为空或与任务派发人/参与人可见范围相符。标签颜色只从表读取并回传，不接受客户端推导。

开始时间新增 `tasks.start_at timestamptz`；`deadline` 已为 `timestamptz`，请求解析 `OffsetDateTime`，从而要求时区和分钟精度。任务正文保存原始 `content`；反馈时把带时间和作者标识的反馈块追加到 `content` 末尾，并不产生 `progressNote`、`progress` 或完成情况字段。

### 4. 评论、幂等与通知

新增 `task_comments`：ID、公司、任务、作者、正文、可选父评论、客户端去重键、创建时间；唯一键 `(task_id,author_id,client_key)`。评论只可插入，数据库触发器拒绝更新和删除。父评论必须属于同一任务。`POST /api/tasks/{id}/comments` 要求 `Idempotency-Key`，空白/超长文本为 `400`，重复键为 `409 DUPLICATE_COMMENT`，无任务读取权限为 `404`，无评论资格为 `403`。

评论服务用一个 Spring 事务依次写评论、审计与现有 `outbox_events`：通知派发人、其余参与人和被回复作者（排除评论作者），每个收件人使用评论 ID 构造稳定去重键。发生任一错误时整体回滚。通知投递与客户端展示留给 D。

### 5. 权限、并发与错误

- 标签直接新增/更新/停用：仅 `FOUNDER`；非创始人 `403`。
- 创建/修改/删除申请：有派发资格的申请者；审核器不能为申请人，由现有审核策略强制。
- 任务详情、列表、评论读取：沿用服务端公司与组织范围；范围外统一 `404`。
- 修改、删除审核生效：候选带 `version`，版本不一致 `409 VERSION_CONFLICT`，不写任务、关联、事件、审计或通知。
- 评论重复、空评论、错误父评论分别返回明确 `409 DUPLICATE_COMMENT`、`400 INVALID_COMMENT`、`400 INVALID_PARENT_COMMENT`。

### 6. 迁移、回滚与验证

主线当前最高版本为 V19，因此实现使用 V20/V21；任务治理原先在分支中的 V16/V17 未发布，合并主线时顺延。迁移仅新增列/表、回填数据、扩展约束和触发器，不能修改 V1–V19。V20 重新创建审核类型约束时保留主线既有 `PROCEDURE` 类型。旧代码在回滚时会忽略新表与 `start_at`，但一旦新接口写入新审核种类，不支持数据库向下迁移；应用回滚须先停止新写入。

单元测试覆盖草稿规范化、参与人去重、标签权限/范围、评论校验和事务失败；集成测试使用 PostgreSQL/Redis 覆盖创建/修改/删除批准和驳回、时区、范围、单标签、评论回复/通知、重复与版本冲突。最终运行后端验证和 OpenSpec 严格校验，并记录实际结果。

## Open Questions

- Issue 与 Sprint 编号尚未提供；实施完成前须由项目负责人创建/关联，不能编造编号。
