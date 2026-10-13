## 1. 数据迁移

- [x] 1.1 新增 `server/src/main/resources/db/migration/V4__task_dispatch.sql`：`idempotency_keys` 末尾追加 `created_at`、`hash_version`（默认 1），`attachments` 未绑定部分索引，`task_events` 类型 CHECK、`(task_id,sequence)` 索引及 UPDATE/DELETE/TRUNCATE 只追加触发器；在空库与已有 V1–V3 数据的库上启动应用，验证 Flyway 执行成功
- [x] 1.2 在集成测试中直接执行 `UPDATE`/`DELETE task_events`，验证数据库拒绝且时间线不变

## 2. 模块骨架与可见性

- [x] 2.1 创建 `server/src/main/java/cn/workpanel/module/task` 包及 `TaskDraft`、`TaskView` 类型；将 `Actor`、`Db`、`ApiError` 中新包需要的成员改为 `public`（行为不变），验证 `mvn -q compile` 通过

## 3. 规范化与校验

- [x] 3.1 实现 `TaskDraftNormalizer`：字段白名单、`SERVER_MANAGED_FIELD` 拒绝、标题/文本长度、带时区截止时间、紧急度默认与取值、协作人与附件去重排序并剔除主负责人；编写 `TaskDraftNormalizerTest` 覆盖上述分支并通过
- [x] 3.2 实现 v2 规范化摘要与 v1 旧摘要兼容比较；单元测试验证顺序/重复不同的请求摘要相同、内容不同摘要不同、v1 记录按旧算法比较

## 4. 参与人、附件、时间线、读取范围

- [x] 4.1 实现 `TaskParticipants`：主负责人与协作人同公司、`ACTIVE`、在派发人可见范围内，写入 `PRIMARY`/`COLLABORATOR`；单元测试覆盖范围外、非在职、其他公司用户
- [x] 4.2 实现 `TaskAttachments`：仅本人未绑定附件可引用，他人 403、不存在 404、已绑定其他任务 409 `ATTACHMENT_BOUND`，支持修订场景同任务附件；编写 `TaskAttachmentsTest` 并通过
- [x] 4.3 实现 `TaskTimeline`（追加与按序号读取）和 `TaskAccess`（与现有任务范围语义一致，范围外 404）；单元测试验证范围 SQL 参数与 404 行为

## 5. 派发服务与接口

- [x] 5.1 实现 `TaskDispatchService`：资格与格式校验 → advisory 锁 → 幂等记录比较（重放返回当前详情且跳过副作用 / 冲突 409 / 新建）→ 显式 `DISPATCHED`、版本 1 插入 → 参与人、附件、`DISPATCHED` 事件、幂等记录（`hash_version=2`）、审计、既有 outbox 写入同一事务；编写 `TaskDispatchServiceTest` 覆盖新建、重放、冲突、校验失败不加锁
- [x] 5.2 实现 `TaskDispatchController`（`POST /api/tasks`、`GET /api/tasks/{id}`），从 `Tasks.java` 移除对应端点；验证路由无重复映射、应用启动成功
- [x] 5.3 `Business.validateTask/assign/taskDto` 改为委托新模块，`AiApi.confirm` 改调 `TaskDispatchService`，`Reviews` 任务修订改用 `TaskParticipants`/`TaskAttachments`（同任务附件允许）；验证 `BackendIntegrationTest` 全部通过
- [x] 5.4 更新 OpenAPI `TaskDraft` 与派发接口描述：`Idempotency-Key` 头、`IDEMPOTENCY_CONFLICT`、`ATTACHMENT_BOUND`、`SERVER_MANAGED_FIELD`；访问 `/api/openapi` 验证新错误码与头部出现

## 6. 集成测试

- [x] 6.1 新增 `server/src/test/java/cn/workpanel/module/task/TaskDispatchIntegrationTest`（真实 PostgreSQL/Redis）：正常生命周期派发→接收→反馈→验收→归档，验证时间线顺序及首条事件不变
- [x] 6.2 幂等场景：相同请求重放、协作人/附件顺序不同重放、8 线程并发重放只产生一个任务和一条 `DISPATCHED` 事件、同键不同内容 409、不同派发人同键互不影响、状态变化后重放返回当前状态
- [x] 6.3 非法状态与校验：携带 `phase`/`version`/完成情况字段 400、未知字段 400、缺少名称/截止时间不带时区/紧急度非法 400、缺少或超长幂等键 400、无资格 403，并断言均无残留记录；正常派发响应为 `DISPATCHED`、版本 1 且不含完成情况字段
- [x] 6.4 越权读取：其他团队团队长、其他部门员工、其他公司用户读取详情 404，响应不含任务字段；参与人与上级可读
- [x] 6.5 附件与回滚：自有附件绑定并可被主负责人下载、他人附件 403、不存在或其他公司附件 404、已绑定附件 409 且无新任务、参与人写入失败时无任务/事件/幂等记录/附件绑定残留
- [x] 6.6 负责人与协作人：协作人重复且含主负责人时详情去重；指派其他团队、其他公司、`PENDING`/`DISABLED` 用户时 403/404 且不创建任务

## 7. 交付校验

- [x] 7.1 在 `server` 目录运行 `mvn -q test`，单元测试与集成测试全部通过
- [x] 7.2 在仓库根目录运行 `openspec.cmd validate --all --strict` 通过
