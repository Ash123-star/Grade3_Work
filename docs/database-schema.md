# 后端数据库字段说明

本文说明当前运行 Spring Boot 后端使用的 PostgreSQL 数据库。实际启动时使用 `server/src/main/resources/db/migration/` 的 Flyway 迁移；`deploy/postgresql/` 是独立的数据基础设施包，字段模型和 ID 类型不同，不能把两套脚本混合执行。

## 使用约定

- `company_id`：公司租户标识。所有业务表都必须沿公司外键关联，服务端查询还要额外执行角色和组织范围检查。
- `id`：业务对象唯一标识，当前后端使用文本 ID；客户端只能使用 API 返回的 ID。
- `version`：乐观并发版本。新增对象从 `0` 作为请求版本，数据库记录从 `1` 开始；更新必须携带当前版本。
- `created_at`、`submitted_at`、`decided_at` 等时间字段使用 PostgreSQL `timestamptz`，保存 UTC。日报的 `business_date` 是 Asia/Shanghai 业务日期。
- `body`、`input`、`output`：JSONB 载荷，只保存对应模块的业务内容。密码、手机号、API Key 和私人备注不得写入 AI 输入。

## 组织与权限

| 表 | 字段 | 作用 |
|---|---|---|
| `companies` | `id`, `name` | 公司租户及名称 |
| `companies` | `version`, `review_policy` | 公司配置版本和任务审核层级策略 |
| `departments` | `id`, `company_id`, `name` | 部门及所属公司 |
| `teams` | `id`, `company_id`, `department_id`, `name` | 团队及部门归属 |
| `users` | `id`, `company_id`, `account`, `password_hash` | 登录身份和密码摘要 |
| `users` | `phone`, `name`, `profile` | 手机号、姓名和个人资料；手机号不能重复 |
| `users` | `department_id`, `team_id` | 组织归属；复合外键防止跨公司或跨部门团队引用 |
| `users` | `role`, `status` | 主角色和 `PENDING/ACTIVE/DISABLED` 状态 |
| `users` | `must_change_password` | 是否必须首次改密 |
| `users` | `dispatch_enabled`, `company_reviewer` | 派发资格和独立公司复核职责开关 |
| `roles` | `id` | `ADMIN/FOUNDER/DIRECTOR/LEADER/EMPLOYEE` 角色代码 |
| `permissions` | `id` | 权限代码；当前主要用于保留权限目录 |
| `user_roles` | `user_id`, `role_id` | 角色关联表；应用修改角色时需与 `users.role` 同步 |
| `reporting_relations` | `employee_id`, `manager_id`, `company_id` | 直属汇报关系；V4 触发器阻止直接和间接循环 |
| `sessions` | `token_hash`, `user_id`, `expires_at` | 会话摘要、所属用户和过期时间 |

## 导图、任务和附件

| 表 | 字段 | 作用 |
|---|---|---|
| `dashboard_items` | `kind`, `owner_id` | `COMPANY` 公司重点或 `PERSONAL` 个人重点 |
| `dashboard_items` | `title`, `body`, `pinned`, `archived`, `position` | 重点内容、置顶、归档和排序 |
| `private_notes` | `owner_id`, `resource`, `object_id`, `text` | 仅本人可见的任务或公司重点备注 |
| `tasks` | `issuer_id`, `owner_id` | 派发者和唯一主负责人 |
| `tasks` | `title`, `deadline`, `body` | 任务标题、截止时间和表单字段；不保存派发页面的完成情况字段 |
| `tasks` | `phase`, `version` | 后台流转阶段和并发版本 |
| `task_assignees` | `task_id`, `user_id`, `kind` | 主负责人或协作者；主负责人由唯一索引保证只有一名 |
| `task_events` | `sequence`, `type`, `actor_id`, `body` | 任务事件时间线，包含派发、接收、反馈、验收、撤回、归档和修订 |
| `attachments` | `owner_id`, `filename`, `content_type`, `data` | 附件元数据和二进制内容；授权由服务端再次判断 |
| `attachments` | `task_id` | 已关联任务；未关联时只有上传者可见 |

## 日报

| 表 | 字段 | 作用 |
|---|---|---|
| `daily_logs` | `owner_id`, `business_date` | 日报所有者和业务日期；二者唯一保证每天一份主日报 |
| `daily_logs` | `body` | `work`、`blockers`、`tomorrow`、`hours`、兼容字段 `taskIds` |
| `daily_logs` | `submitted`, `submitted_at`, `version` | 草稿/已提交状态、提交时间和并发版本 |
| `log_tasks` | `company_id`, `log_id`, `task_id` | 日报与任务的结构化关系；V4 增加跨公司复合外键 |
| `log_versions` | `log_id`, `version`, `body` | 已提交日报及审核生效修订的历史版本 |
| `log_reads` | `log_id`, `reader_id`, `read_at` | 阅读记录，不修改日报正文 |
| `log_comments` | `log_id`, `actor_id`, `text` | 独立日报评语 |

`daily_logs.body.taskIds` 为现有客户端兼容字段，后端保存草稿和审核生效时同步 `log_tasks`。后续统计和关联查询应优先使用 `log_tasks`。

## 审核与审计

| 表 | 字段 | 作用 |
|---|---|---|
| `review_requests` | `kind`, `target_id`, `applicant_id` | 被审核对象、对象 ID 和申请人 |
| `review_requests` | `expected_version`, `before_value`, `candidate` | 版本基线、原值和候选值 |
| `review_requests` | `reason`, `status` | 变更理由和 `PENDING/APPROVED/REJECTED` 状态 |
| `review_steps` | `request_id`, `applicant_id`, `reviewer_id`, `position` | 审核申请人、审核人和审核顺序；V4 禁止审核人等于申请人 |
| `review_steps` | `state`, `reason`, `decided_at` | 步骤结果、驳回理由和决定时间 |
| `audit_records` | `actor_id`, `type`, `object_id` | 操作者、审计事件和对象 |
| `audit_records` | `before_value`, `after_value`, `reason` | 修改前后内容和理由 |

## 消息与幂等

| 表 | 字段 | 作用 |
|---|---|---|
| `outbox_events` | `dedup_key`, `recipient_id`, `type`, `object_id` | 事务内写入的待投递通知，去重键防止重复提醒 |
| `outbox_events` | `delivered_at` | 成功投递到站内通知的时间 |
| `notifications` | `sequence`, `recipient_id`, `is_read` | SSE 顺序号、接收人和已读状态 |
| `idempotency_keys` | `actor_id`, `key`, `request_hash`, `task_id` | 派发请求幂等键、请求摘要和最终任务 |

## AI 地图

| 表 | 字段 | 作用 |
|---|---|---|
| `ai_jobs` | `owner_id`, `state`, `input`, `output` | AI 请求所有者、执行状态、脱敏输入和建议草稿 |
| `ai_jobs` | `partial`, `tokens`, `version`, `error` | 流式中间文本、用量、编辑版本和失败信息 |
| `ai_map_nodes` | `owner_id`, `job_id`, `body` | 归用户所有的 AI 地图节点及来源 |
| `ai_map_edges` | `owner_id`, `source_id`, `target_id`, `body` | 节点关系；复合外键保证节点属于同一用户和公司 |

## 开发规则

新增字段先判断是否是稳定关系。跨表引用、统计维度、权限边界和需要唯一性的内容应使用列或关系表；仅用于展示且结构变化频繁的内容才放入 JSONB。已发布迁移不可修改，必须追加新的 `V` 版本，并同步 OpenSpec、后端代码、字段字典和集成测试。
