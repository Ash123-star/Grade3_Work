# Design

## Context

当前后端已有认证、组织范围、任务事件、日报已读登记、AI 作业和普通任务确认路径。Flutter 已接入这些现有路径，但通用反馈资源会产生未实现的 `/feedback` 读取请求；任务退回补充、阅读人员列表、AI 显式范围和确认原子版本仍缺少完整契约。具体背景与证据见 `docs/backend-interface-gaps.md`。

## Goals / Non-Goals

**Goals:**

- 以运行时 OpenAPI 为双端唯一契约来源，补齐缺口后同步服务端、客户端和文档。
- 保持模块化单体结构，权限、状态、版本、幂等和审计逻辑位于服务端应用/领域层。
- 让反馈、任务补充和阅读查询复用现有公司/组织范围规则；让 AI 继续只由服务端调用 DeepSeek。
- 对客户端可能请求的未实现反馈路径先建立阻断或正式替代，禁止静默猜测。

**Non-Goals:**

- 本变更不预先决定新 URL、请求字段、数据库表名或 UI 主题。
- 不把 Mock 列表、HTTP 适配器测试或客户端隐藏操作当作后端能力。
- 不引入微服务、消息队列或新的数据库；除非设计评审证明现有模块无法满足一致性要求。

## Decisions

### 1. 先定契约，再分模块实现

候选路线一是扩展现有 `/tasks/{id}/events`、`/ai/jobs/{id}/confirm-task` 等路径，优点是兼容当前客户端和已有权限/幂等代码；路线二是为每个缺口建立独立资源路径，边界清晰但增加 DTO、迁移和客户端映射。推荐优先扩展现有命令边界，只有反馈和阅读清单等独立查询无法自然归属时才创建新资源。两条路线都必须通过 OpenAPI、集成测试和客户端适配评审。

### 2. 复用服务端范围和事务边界

所有新查询调用现有 Actor/company/组织范围规则。退回补充和 AI 确认使用数据库事务、乐观版本和幂等键；通知通过已有 outbox 语义写入。阅读清单不返回私人备注、密码、手机号或无关审核信息。

### 3. AI 继续服务端托管密钥

范围筛选只作为受服务端校验的业务条件，不能把数据库查询或 DeepSeek 密钥暴露给 Flutter。确认时重新加载 job、来源和 Actor 范围，版本不匹配即拒绝。

### 4. Flutter 适配保持显式失败

契约实现前，Flutter 对反馈提交和退回补充继续返回明确“不支持”状态；反馈列表不得继续把未实现 `/feedback` 当作成功资源。契约定案后再添加正式 Repository 映射和 HTTP/UI 测试。

## Risks / Trade-offs

- [路径和字段尚未定案] → 在设计评审前不修改 Flutter 请求；以 OpenAPI 运行时快照作为合并门槛。
- [状态扩展可能影响统计和通知] → 先更新任务状态机、事件投影和 outbox 集成测试，再接客户端。
- [阅读清单涉及人员隐私] → 只允许日志可见范围查询，返回最小字段并覆盖无记录/越权场景。
- [AI 确认存在并发竞争] → 使用 job version + 来源重验 + 幂等键同事务保护，增加并发集成测试。
- [数据库结构可能需要迁移] → 只新增 `server` Flyway 版本，禁止修改已发布迁移；若可复用现有 JSONB/事件结构则不新增表。

## Migration Plan

1. 先冻结五项缺口的角色、状态、请求/响应、错误、幂等和审计决策。
2. 更新 OpenSpec、后端 Controller/application/domain/infrastructure、Flyway（如需要）、SpringDoc 和接口文档。
3. 运行后端真实 PostgreSQL/Redis 集成测试，再接入 Flutter 正式 Repository 和契约测试。
4. 发现客户端仍请求未定案路径时，先发布客户端阻断/明确错误；契约和服务端部署后再启用入口。
5. 回滚时保留旧任务/日志/AI 数据，关闭新入口；数据库迁移按新增版本的兼容策略处理。

## Contract decisions required before implementation

The implementation design and owner assignment must resolve, document, and compare:

- Feedback lifecycle and whether manager handling state/SLA is required.
- Whether return-for-supplement extends the existing task event route or uses a separate command resource.
- Which selectable AI scopes are allowed by each role, while always intersecting with Actor authorization.
- Exact paths, DTO fields, errors, pagination, idempotency, version preconditions, persistence and rollback.

No route or DTO is frozen by this tracking change. Implementation tasks MUST NOT start until these decisions have an approved design and acceptance matrix.
