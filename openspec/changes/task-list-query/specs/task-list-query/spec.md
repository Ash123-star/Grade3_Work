## Purpose

定义任务列表的服务端查询契约：仅在调用者的组织数据范围内返回任务，并通过显式字段白名单防止完成情况、阶段或替代状态泄露。

## ADDED Requirements

### Requirement: 任务列表字段白名单

系统 SHALL 通过 `GET /api/tasks` 返回 `items`、`total` 和 `nextCursor`。每个 `items` 元素 MUST 只包含 `id`、`owner_id`、`issuer_id`、`title`、`deadline`、`version`、`created_at`；实现 SHALL NOT 返回 `phase`、`status`、`completion`、`progress`、`done`、`accepted`、`archived`、`withdrawn` 或可替代这些业务含义的字段，也不得返回未过滤的 `body`、事件或审核信息。

#### Scenario: 正常列表不泄露任务完成情况
- **WHEN** 有读取范围的用户分页查询任务
- **THEN** 每条任务只含白名单字段，响应中不含 `phase`、完成情况、状态或等效替代字段

#### Scenario: 已验收或已归档任务仍不泄露阶段
- **WHEN** 列表中同时存在已验收、已归档和未接收的任务
- **THEN** 返回的条目之间不以字段、布尔值、进度、事件摘要或状态文本暴露其生命周期阶段

### Requirement: 组织范围过滤

系统 SHALL 在服务端对列表应用公司隔离和组织数据范围。员工 MUST 仅看到自己作为主负责人、协作人或派发人参与的任务；有组织穿透范围的上级 SHALL 只看到覆盖范围内主负责人的任务；管理员和创始人可读取本公司任务。其他公司的任务或范围外任务 MUST NOT 出现在列表中。

#### Scenario: 员工只读取参与任务
- **WHEN** 员工查询任务列表
- **THEN** 返回其负责、协作或派发的同公司任务，不返回同团队但与其无关的任务

#### Scenario: 上级读取组织范围内任务
- **WHEN** 团队长或部门老总查询列表
- **THEN** 返回其组织范围内主负责人的任务，并保留字段白名单

#### Scenario: 跨公司和范围外任务被隐藏
- **WHEN** 调用者查询列表，库中存在其他公司或其组织范围外的任务
- **THEN** 这些任务不出现在 `items`、`total` 或分页结果中

### Requirement: 查询参数与授权失败

系统 SHALL 支持 `search`、`ownerId`、`date`、`period`、`cursor` 和 `limit`。`search` SHALL 仅匹配标题；`date` 与 `period` SHALL 使用带时区截止时间范围。分页或日期参数非法 MUST 返回 400 且不查询任务。若 `ownerId` 不属于同公司，系统 MUST 返回 404；若属于同公司但不在调用者可见组织范围，系统 MUST 返回 403，且不返回任何列表数据。

#### Scenario: 有效筛选与稳定分页
- **WHEN** 调用者以有效 `search`、日期范围和分页参数查询
- **THEN** 系统仅返回同时命中标题和截止时间范围的可见任务，按 `deadline`、`id` 稳定排序，并返回可继续使用的 `nextCursor`

#### Scenario: 越权负责人筛选被拒绝
- **WHEN** 团队长以其范围外同公司用户作为 `ownerId` 查询
- **THEN** 系统返回 403 `FORBIDDEN`，不返回任务条目或总数

#### Scenario: 非法查询参数
- **WHEN** `cursor`、`limit`、`date` 或 `period` 非法
- **THEN** 系统返回 400，且不泄露或写入任何任务数据

### Requirement: 列表查询性能迁移

系统 MUST 通过新的 Flyway 迁移建立支持公司内截止时间和稳定分页的读取索引。迁移 SHALL 为前向版本 `V7__task_list_query_index.sql`，不得修改 V1–V6 或任务数据。

#### Scenario: 已有数据库升级
- **WHEN** 包含 V1–V6 数据的数据库启动新版服务
- **THEN** Flyway 成功应用 V7，已有任务、参与人、事件和版本数据不被修改
