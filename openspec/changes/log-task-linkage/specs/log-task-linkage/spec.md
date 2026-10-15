## Purpose

定义下属日报入口、草稿私密性、组织范围过滤和日报任务关联的服务端契约。

## ADDED Requirements

### Requirement: 下属日志固定入口和组织范围

系统 SHALL 通过 `GET /api/logs/subordinates` 提供下属日报入口。该入口 MUST 仅允许管理者调用，只返回调用者组织范围内、非本人、已提交的日报。`ownerId` 为其他公司用户时 MUST 返回 404；为同公司但组织范围外用户时 MUST 返回 403；员工调用 MUST 返回 403。

#### Scenario: 管理者读取已提交下属日报
- **WHEN** 团队长访问下属入口
- **THEN** 系统仅返回本团队已提交的他人日报，按业务日期倒序，且 `total` 只统计这些日报

#### Scenario: 员工或越权筛选被拒绝
- **WHEN** 员工访问下属入口，或团队长以其他团队成员作为 `ownerId` 筛选
- **THEN** 系统返回 403，响应不包含日志条目或总数

### Requirement: 草稿不可见

系统 SHALL 在日志详情、普通列表、下属入口、版本、已读和评语接口中对非本人隐藏未提交草稿。非本人按草稿 ID 请求 MUST 返回 404，不得返回正文、任务 ID、版本、评语或已读信息。

#### Scenario: 管理者无法通过下属入口发现草稿
- **WHEN** 下属保存但未提交日报，管理者查询下属入口或按其 `ownerId` 查询
- **THEN** 响应不包含该草稿，`total` 不计入该草稿

### Requirement: 日志任务关联

系统 SHALL 将 `body.taskIds` 与 V4 `log_tasks` 保持一致。保存草稿、提交修订申请和审核通过应用修订时，系统 MUST 验证每个任务 ID 在申请人的当前服务端读取范围内；任务不存在或越权时 SHALL 拒绝整个写入，不修改日报正文或 `log_tasks`。相同任务 ID SHALL 只关联一次。

#### Scenario: 保存可见任务关联
- **WHEN** 用户保存引用自己可读取任务的日报草稿
- **THEN** 同一事务内更新正文和 `log_tasks`，每个去重任务 ID 恰有一条关联

#### Scenario: 草稿引用范围外任务
- **WHEN** 用户保存包含其他团队或其他公司的任务 ID 的草稿
- **THEN** 系统返回 404，日报版本、正文和原有 `log_tasks` 均不改变

#### Scenario: 审核期间失去任务访问权
- **WHEN** 已提交日报的修订候选包含任务关联，申请人在审核通过前失去该任务读取范围
- **THEN** 修订生效被拒绝，当前正文、版本和 `log_tasks` 保持不变

### Requirement: 下属查询索引迁移

系统 MUST 通过前向 Flyway 迁移 `V9__log_task_linkage_index.sql` 创建已提交日报的负责人和日期部分索引，且 SHALL NOT 修改 V1–V8、V4 `log_tasks` 数据或外键。

#### Scenario: 存量数据库升级
- **WHEN** 已有 V1–V8 数据的数据库启动新版服务
- **THEN** Flyway 成功应用 V9，已有日志任务关联和草稿私密规则继续有效
