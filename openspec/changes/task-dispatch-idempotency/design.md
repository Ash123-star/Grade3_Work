## Context

现有后端是单包 `cn.workpanel`，派发逻辑分散在 `Tasks.create`、`Business.validateTask/assign/taskDto/taskScope`，`AiApi.confirm` 和 `Reviews`（任务修订生效）也直接调用这些静态方法。已有表：`tasks`、`task_assignees`（`PRIMARY`/`COLLABORATOR`，单主负责人唯一索引）、`task_events`（bigserial 序号）、`idempotency_keys`（主键 `actor_id,key`）、`attachments`（`task_id` 可空）。Flyway 已到 V3。

已知缺陷：
- 幂等摘要基于原始请求 `TreeMap`，协作人/附件顺序或重复不同就被判为冲突。
- 附件校验允许引用“可见任务中的他人附件”，而绑定时又因已绑定其他任务抛 409，规则自相矛盾。
- `task_events` 无只追加保护，事件类型无约束。
- 越权读取依赖 `Db.one` 抛 404，但没有针对派发的单元测试。

本变更是任务与日报后端 5 个变更中的第 1 个，只处理派发、幂等、参与人、附件引用、事件时间线与详情读取范围。

## Goals / Non-Goals

**Goals:**
- 在 `cn.workpanel.module.task` 建立派发模块，其它模块通过它派发和读取任务。
- 幂等基于规范化请求，重放结果稳定，并发安全。
- 附件引用规则单一且可测试。
- 事件时间线在数据库层只追加。
- 单元测试覆盖规范化、校验、幂等判定；集成测试覆盖生命周期、重放、非法状态、越权读取。

**Non-Goals:**
- 状态机重构、转派、改期、乐观锁规则（变更 2）；任务列表（变更 3）；日报与日志关联（变更 4、5）。
- 组织审核链（`Reviews` 保持原样，只替换其调用的参与人写入组件）。
- 通知投递：保留现有 outbox 写入，不改 SSE/投递逻辑。
- AI provider、DeepSeek 调用与密钥管理：本变更不涉及；`AiApi.confirm` 仅改为调用新派发服务，密钥仍只在服务端配置。
- Flutter/Web 接口调用改造。

## Decisions

### 1. 包结构与依赖方向
```
cn.workpanel.module.task
├── TaskDispatchController   POST /api/tasks, GET /api/tasks/{id}
├── TaskDispatchService      派发事务、幂等、调用下列组件
├── TaskDraft                规范化后的派发内容（record）
├── TaskDraftNormalizer      字段白名单、服务端字段拒绝、去重排序、默认值（纯函数，可单测）
├── TaskParticipants         负责人/协作人校验与写入
├── TaskAttachments          附件引用校验与绑定
├── TaskTimeline             事件追加与读取
├── TaskAccess               详情读取范围（复用 Business.taskScope 的 SQL 语义）
└── TaskView                 详情 DTO 组装（不含完成情况字段）
```
新模块依赖 `Db`、`Actor`、`ApiError`；旧代码依赖新模块，反向不允许。`Business.validateTask/assign/taskDto` 改为薄委托，供 `Reviews`、`Dashboard`、`Analytics`、`Ai` 继续使用，避免本次大范围改动。`Tasks.java` 删除 `create`、`detail`，保留 `list`、`event`、`revision`，留给变更 2/3 迁移。
备选：一次性迁走全部任务代码。放弃原因：与变更 2/3 范围重叠，评审困难。

### 2. 幂等规范化与摘要
`TaskDraftNormalizer` 输出 `TaskDraft`：`title` 去首尾空白；`urgency` 缺省 `NORMAL`；`collaborators` 去重、移除 `ownerId`、排序；`attachments` 去重、排序；可选文本字段缺省不写入。摘要 = SHA-256(规范化 JSON，键有序)。`body` 存规范化内容，因此详情、修订候选和重放看到的是同一份数据。
- 锁：沿用 `pg_advisory_xact_lock(hashtextextended(actor:key,0))`，在校验之后、读取幂等记录之前获取；同一事务内插入幂等记录。主键 `(actor_id,key)` 作为最后防线，若违反唯一约束则回读已有记录走重放分支。
- 重放：摘要相同时返回 `TaskView` 当前详情（状态可能已不是 `DISPATCHED`），并跳过参与人、附件、事件、通知写入。
- 重放读取不再走 `taskScope`：派发人永远能读取自己派发的任务；直接按 `company_id + issuer_id + id` 读取，避免派发人后来组织变动导致重放 404。
- 校验顺序：先校验派发资格和请求格式，再加锁比较摘要。这意味着派发资格被撤销后的重放返回 403，而不是旧结果，符合“无资格直接调用即拒绝”。
- 历史记录兼容：V4 之前的幂等记录摘要基于原始请求。新增 `hash_version` 列（旧记录为 1，新记录为 2）；v1 记录按旧算法（原始请求 `TreeMap`）比较，保证升级前后同一请求重放结果一致。

### 3. 服务端字段与初始状态
白名单之外的字段统一 400 `UNKNOWN_FIELD`；其中 `phase`、`version`、`status`、`completion`、`completed`、`progress`、`issuerId`、`id` 单独返回 400 `SERVER_MANAGED_FIELD`，便于客户端定位。插入时显式写 `phase='DISPATCHED', version=1`，不依赖列默认值。

### 4. 附件引用
规则：`attachments.company_id = actor.company AND owner_id = actor.id AND task_id IS NULL`，以 `FOR UPDATE` 锁定后绑定。不存在或属于其他公司返回 404；他人附件返回 403；已绑定其他任务返回 409 `ATTACHMENT_BOUND`。修订生效（`Reviews`）路径中，已绑定到同一任务的附件视为合法，由 `TaskAttachments.bind(taskId, ids, allowSameTask=true)` 区分。下载授权 `Attachments.download` 不变。
备选：保留“可引用可见任务的附件”。放弃原因：附件只能绑定一个任务，这种引用必然在绑定时失败。

### 5. 事件时间线只追加
V4 新增触发器函数 `task_events_append_only()`，对 `UPDATE`、`DELETE` 抛异常；`TRUNCATE` 通过语句级触发器同样拒绝。事件类型加 CHECK：`DISPATCHED, RECEIVED, FEEDBACK, ACCEPTED, ARCHIVED, WITHDRAWN, REVISED`（变更 2 扩展时用新迁移替换约束）。读取按 `sequence` 升序。现有集成测试不删除事件行，不受影响；新测试如需清理，使用独立数据并依赖测试库重建，不删除事件。

### 6. 读取范围与跨端契约
`TaskAccess.readable(actor, id)` 使用与 `Business.taskScope` 相同条件：同公司，且为派发人、参与人，或主负责人在 `Actor.userScope` 内。范围外统一 404 `NOT_FOUND`。错误体保持 `{code,message,traceId}`。OpenAPI 的 `TaskDraft` 补充 `Idempotency-Key` 头说明和新错误码，Web 与 Flutter 共用该契约；客户端只负责隐藏入口，授权只在服务端。

### 7. 数据迁移 V4__task_dispatch.sql
- `idempotency_keys` 在末尾增加 `created_at timestamptz NOT NULL DEFAULT now()`、`hash_version smallint NOT NULL DEFAULT 1`；主键 `(actor_id, key)` 不变（用户 ID 全局唯一，已隐含公司隔离）。
- `attachments` 增加部分索引 `(company_id, owner_id) WHERE task_id IS NULL`。
- `task_events` 增加类型 CHECK、只追加触发器、索引 `(task_id, sequence)`。
- 只做增量变更，不重写历史数据；在空库和带 V1–V3 数据的库上都可执行。

### 8. 测试策略
- 单元测试（JUnit 5 + Mockito，`server/src/test/java/cn/workpanel/module/task/`）：`TaskDraftNormalizerTest`（去重排序、默认值、服务端字段、未知字段、长度与日期）、`TaskDispatchServiceTest`（新建/重放/冲突分支、校验失败不加锁、重放跳过副作用）、`TaskAttachmentsTest`（自有/他人/已绑定/同任务）。
- 集成测试 `TaskDispatchIntegrationTest`：复用 `BackendIntegrationTest` 的 PostgreSQL/Redis 启动方式和用户夹具，覆盖正常生命周期（派发→接收→反馈→验收→归档，时间线顺序）、幂等重放（顺序不同、并发 8 线程）、同键冲突、非法初始状态、状态变化后重放、越权读取（其他团队/部门/公司）、附件规则、事件篡改被拒、事务回滚无残留。
- 现有 `BackendIntegrationTest` 必须保持通过。

## Risks / Trade-offs

- [旧客户端依赖“引用他人可见附件”] → 现实现中该路径必然以 409 失败，实际无可用依赖；在 OpenAPI 中注明新错误码。
- [只追加触发器影响测试清理或运维修数] → 测试改用 schema 重建；运维修数需由迁移显式临时禁用触发器并留审计。
- [hash_version 双算法增加复杂度] → 仅用于读取历史记录，新记录全部为 v2；后续可在确认无旧键后用迁移清理。
- [`Business` 委托层暂留，代码重复] → 变更 2/3 迁移完成后移除。
- [派发人组织变动后重放] → 按派发人身份读取，保证重放稳定；但派发资格被撤销时返回 403，属于有意取舍。

## Migration Plan

1. 部署包含 V4 的版本，Flyway 自动执行；V4 只增不删，可在线执行。
2. 回滚：应用回滚到旧版本时 V4 新增列有默认值，旧代码插入 `idempotency_keys` 使用位置参数 `VALUES (?,?,?,?,?)`，因此 V4 必须把新列放在末尾，保证旧代码兼容；触发器对旧代码无影响（旧代码不修改事件）。
3. 不提供 V4 的向下迁移；需要时以新的前向迁移撤销。

## Open Questions

（无。附件规则、重放读取身份、服务端字段错误码均已在上文决定；如需调整请在确认时提出。）
