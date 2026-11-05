## Why

原始调查发现列表查询直接拼接SQL并复用详情DTO，需要收敛为任务模块只读用例和显式投影。2026-11-05用户确认任务管理列表展示真实完成情况，覆盖旧全面禁显目标；派发表单仍不显示。现行目标是明确流转映射和兼容契约，在授权范围内展示，不泄露未过滤事件或审核数据。实际实现须重新核对当前源码，旧调查不表示当前仍存在同一缺口。

## What Changes

- 在 `server/src/main/java/cn/workpanel/module/task` 增加任务列表查询应用服务与专用列表 DTO，Controller 仅负责参数、身份和响应映射。
- 支持 `search`、`ownerId`、`date`、`period`、`cursor`、`limit` 查询；统一服务端组织范围过滤和稳定排序分页。
- 列表响应固定为公开的识别、负责人、派发人、标题、截止时间、创建时间和版本字段；不得返回 `phase`、`status`、`completion`、`progress`、`done` 或任何等效状态/完成字段，也不得用布尔值或计数替代。
- 新增 Flyway 迁移 `V7__task_list_query_index.sql`，为公司内截止时间、稳定分页的读取建立索引。
- 补充单元测试、真实 PostgreSQL/Redis 集成测试、OpenAPI 契约和验证记录。

## Capabilities

### New Capabilities
- `task-list-query`: 在组织数据范围内查询任务列表，按2026-11-05确认提供真实完成情况，保留显式字段投影、分页及范围隔离。

### Modified Capabilities
（无。任务详情和生命周期接口保持原有契约。）

## Impact

- 代码：`module/task` 增加查询应用服务、列表投影和输入校验；`TaskController.list` 改为委托；为避免导图等既有聚合列表绕过白名单，旧 `detail=false` 任务投影也改用相同安全视图。
- API：`GET /api/tasks` 的列表条目成为显式白名单契约；这是为了安全移除任何未约定的详情字段。
- 数据库：V7 仅新增读取索引，不改写任务数据或历史迁移。
- 非目标：不增加任务状态筛选、不实现审核链、通知投递、AI provider 或 Flutter 调用；日报和日志任务关联留给后续变更。
