## Context

当前 `TaskController.list` 直接使用 `Business.taskScope` 拼接筛选 SQL，并把 `SELECT t.*` 的结果传入详情 DTO。虽然 DTO 当前未展示阶段，但查询边界和字段白名单不在独立模块内，后续改动容易把 `phase`、完成字段或 `body` 中的进度信息带回列表。现有 `tasks_scope(company_id, owner_id, deadline)` 不能直接覆盖列表的 `company_id + deadline + id` 稳定排序。

## Goals / Non-Goals

**Goals:**
- 所有列表请求都在服务端应用公司和组织数据范围。
- 通过专用投影保证列表不包含完成、状态或替代状态。
- 以固定字段和稳定排序提供可验证分页。

**Non-Goals:**
- 不通过列表暴露生命周期、进度或验收结论。
- 不新增状态筛选、全文搜索基础设施、批量操作或前端调用。
- 不修改组织审核、通知投递、AI provider、日志模块。

## Decisions

### 1. 查询服务与字段白名单

新增 `TaskQueryService.list(Actor, Query)`。服务使用 `Business.taskScope(actor)` 生成范围条件，但只选择 `id`、`owner_id`、`issuer_id`、`title`、`deadline`、`version`、`created_at`。`TaskListView` 显式构造响应；不得传递 `tasks.body` 或 `SELECT t.*` 给列表序列化。兼容旧聚合列表的 `Business.taskDto(..., false)` 也返回该投影，避免导图等入口绕过字段白名单。

备选方案是继续复用详情 DTO 后在 Controller 移除字段。放弃原因是详情 DTO 或表字段增加时可能重新泄露字段，且无法在编译结构上表达列表白名单。

### 2. 范围、筛选和错误顺序

查询顺序为：认证身份 → 分页/日期格式（400）→ `ownerId` 是否同公司且在调用者数据范围内（403/404）→ 查询范围。范围外任务永不作为条目返回；按 ID 读取仍由详情接口返回 404。`search` 按标题大小写不敏感匹配；`date + period` 按既有带时区范围工具过滤截止时间。

列表允许组织范围内的上级读取下属任务，但不因此获得修改、验收或状态字段的权限。员工仅可看到自己作为主负责人、协作人或派发人参与的任务，规则与 `Business.taskScope` 一致。

### 3. 分页和索引

查询按 `deadline ASC, id ASC` 排序，并限制 `limit` 为既有 `Business.page` 定义的范围。响应计算 `nextCursor`，客户端不得把它理解为总页数。新增 V7 索引：

```sql
CREATE INDEX tasks_company_deadline_id ON tasks(company_id, deadline, id);
```

它只优化范围内的日期排序和稳定分页；不改变业务数据。Flyway 保持前向迁移，绝不修改已发布的 V1–V6。

### 4. API 与跨端契约

OpenAPI 对 `GET /api/tasks` 定义 `TaskListItem`，并在描述和测试中写明禁止字段。Web 与 Flutter 使用同一服务端响应；客户端隐藏字段不是授权措施。`TaskApi.list` 将返回该白名单语义，其他模块不得绕过查询服务读 `tasks` 表。

## Risks / Trade-offs

- [详情 DTO 与列表 DTO 短期并存] → 通过命名和独立测试防止再次混用；这是用少量重复换取最小暴露面。
- [offset 分页在数据频繁变动时可能出现漂移] → 本变更维持现有 cursor 语义和稳定排序；真正的 keyset 分页作为后续性能优化，不改变当前接口。
- [新索引增加少量写入成本] → 任务表写入量相对读列表低，且索引可由数据库在线建立；迁移不改数据。

## Migration Plan

1. 以 V7 在已经应用 V1–V6 的数据库上新增 `tasks_company_deadline_id`。
2. 发布查询代码和 OpenAPI；不回填、不删除列、不修改历史事件。
3. 回滚时旧代码可忽略新增索引；索引保留，不提供向下迁移。
