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
| `companies` | `version`, `review_policy` | 公司配置版本与旧审核策略兼容载荷；当前固定直属上级单级，MEMBERSHIP由管理员确认，不允许恢复旧多级策略 |
| `departments` | `id`, `company_id`, `name` | 部门及所属公司 |
| `teams` | `id`, `company_id`, `department_id`, `name` | 团队及部门归属 |
| `users` | `id`, `company_id`, `account`, `password_hash` | 登录身份和密码摘要 |
| `users` | `phone`, `name`, `profile` | 手机号、姓名和个人资料；手机号不能重复 |
| `users` | `email`, `gender`, `age` | V22权威资料列；可空，邮箱最长320、性别最长32、年龄为非负整数；简介/头像仍merge至profile，读列不被旧JSON值覆盖 |
| `users` | `employment_start_date` | V22可信入职业务日；历史无来源为NULL，新成员确认生效时写上海日期；NULL不推导缺交 |
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
| `tasks` | `issuer_id`, `owner_id` | 派发者及兼容负责人投影；当前业务参与人以task_participants为准 |
| `tasks` | `title`, `start_at`, `deadline`, `body` | 标题、可空开始时间、截止时间和表单字段；不保存派发页面的完成情况字段 |
| `task_participants` | `task_id`, `user_id`, `company_id` | V20无角色参与人集合，复合外键限制同公司；查询按start_at/deadline与网格区间相交 |
| `tasks` | `phase`, `version` | 后台流转阶段和并发版本 |
| `task_assignees` | `task_id`, `user_id`, `kind` | 主负责人或协作者；主负责人由唯一索引保证只有一名 |
| `task_events` | `sequence`, `type`, `actor_id`, `body` | 任务事件时间线，包含派发、接收、反馈、验收、撤回、归档和修订 |
| `attachments` | `owner_id`, `filename`, `content_type`, `data` | 元数据及历史数据库副本；新文件正文写私有OSS，授权由服务端再次判断 |
| `attachments` | `storage_provider`, `object_key`, `size_bytes`, `file_hash`, `storage_state`, `storage_version`, `storage_updated_at` | V31新增存储来源、完整性和PENDING/READY/DELETING/DELETED状态；仅READY未过期文件可读/绑定 |
| `storage_delete_jobs` | `object_key`, `attachment_id`, `attempts`, `available_at` | 持久化、幂等的外部对象删除与重试 |
| `generated_files` | `owner_id`, `attachment_id`, `kind`, `sources` | 临时CSV/模板产物的全部来源及版本；沿附件有效期拒读，不能作为长期附件绑定 |
| `asset_releases`, `asset_current` | `manifest`, `manifest_hash`, `release_id`, `version` | 不可变全量静态清单与原子激活指针，不含私有用户文件 |
| `attachment_migrations` | `attachment_id`, `object_key`, `file_hash`, `expected_version`, `state` | 历史迁移意图、断点恢复及版本核对；备份/清除/回滚见[OSS说明](oss-storage.md) |
| `attachments` | `task_id` | 已关联任务；未关联时只有上传者可见 |
| `attachments` | `expires_at` | 已有附件有效期；成果反馈引用要求有实际文件且未过期，单次最多5个、任务累计最多100个，绑定与事件同事务 |

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
| `review_requests` | `reason`, `status` | 变更理由和 `PENDING/APPROVED/REJECTED/SUPERSEDED` 状态 |
| `task_pins` | `user_id`, `task_id`, `company_id`, `pinned_at` | V29个人任务置顶；主键(user_id,task_id)，租户外键随用户/任务级联删除；不影响任务version |
| `review_requests` | `approval_mode`, `decision_source` | V22增加DIRECT_MANAGER/ADMIN_MEMBERSHIP/LEGACY模式和DIRECT_MANAGER/ADMIN_MEMBERSHIP/FOUNDER_EXEMPT决定来源；V28增加FOUNDER_PEER模式与决定来源，创始人存量待审在公司另有在职创始人时转为互审，失效审核步骤SUPERSEDED并重新分配，仍无审核人写REVIEW_UNASSIGNED；历史待审迁移不应用候选，已决记录不变 |
| `review_steps` | `request_id`, `applicant_id`, `reviewer_id`, `position` | 审核申请人、审核人和审核顺序；V4 禁止审核人等于申请人 |
| `review_steps` | `state`, `reason`, `decided_at` | 步骤结果、驳回理由和决定时间 |

V22将旧待审步骤标记为SUPERSEDED并保留历史，每个申请至多一个PENDING步骤（部分唯一索引）；旧LOG正文候选失效。接口决定命令携带expectedVersion，重验当前直属关系；MEMBERSHIP不适用创始人免审。
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
| `ai_jobs.input` | `scope` | SELF或AUTHORIZED，旧输入缺失时按AUTHORIZED兼容；worker/retry保留选定范围，不另设重复列 |
| `ai_task_confirmations` | `company_id`, `owner_id`, `job_id`, `client_key` | V23确认回执；复合外键关联同公司同所有者作业，owner/job/key唯一 |
| `ai_task_confirmations` | `job_version`, `action_index`, `request_hash`, `source_refs`, `response` | 原确认版本、0–2行动索引、规范化命令摘要、原来源和原响应；与TASK_CREATE审核同事务，重放前重验来源权限 |
| `ai_map_nodes` | `owner_id`, `job_id`, `body` | 归用户所有的 AI 地图节点及来源 |
| `ai_map_edges` | `owner_id`, `source_id`, `target_id`, `body` | 节点关系；复合外键保证节点属于同一用户和公司 |

## 开发规则

新增字段先判断是否是稳定关系。跨表引用、统计维度、权限边界和需要唯一性的内容应使用列或关系表；仅用于展示且结构变化频繁的内容才放入 JSONB。已发布迁移不可修改，必须追加新的 `V` 版本，并同步 OpenSpec、后端代码、字段字典和集成测试。

## 私人每日事项增量（Issue #63）

`server` Flyway V26 新增 personal_todos 与 personal_todo_commands。前者保存公司、本人、自然日、标题/备注、完成时间、版本、时间戳与软删除标记；后者以公司/本人/幂等键为主键保存请求哈希、原响应及24小时有效期。两表均通过 `(company_id, owner_id)` 复合外键约束归属；未删除事项有按公司/本人/日期/完成状态/创建时间/id 的部分索引。

删除会清除事项正文，但24小时幂等响应可能仍含原正文；过期回执在该用户后续写入时清理，不宣称物理立即擦除。未接入审计正文、AI、导出或组织面板。

V26 原为避开待合并 PR 的 V24/V25 编号选择。五个 PR 整合后，已发布 V26/V27 保持原样，原待发布的创始人互审、任务置顶、多标签迁移分别调整为 V28/V29/V30；不启用 out-of-order。已验证空库与历史基线向 V30 升级。代码回滚可暂保留新增表，不删除历史数据；若确需删表，先备份本人事项和回执并安排独立维护迁移。


## Android必要移动推送

V34新增：并行整合分支已使用V31–V33，故选择V34。本分支基线已有V31 OSS；最终整合仍须统一既有分支的迁移版本与校验值，本功能不修改已发布迁移。

| 表/索引 | 约束与用途 |
| --- | --- |
| `push_preferences` | user主键、公司/用户复合外键；总开关默认false，分类默认true；上海小时范围及起止不同；version乐观锁 |
| `push_devices` | SDK device_id唯一，一台设备仅绑定一个当前会话；session_hash外键ON DELETE CASCADE，binding随机lease，30天不续租清理 |
| `push_deliveries` | notification外键、设备外键ON DELETE CASCADE；通知/设备/lease唯一；状态PENDING/ACCEPTED/CANCELLED/FAILED，attempts<=5，task_version/expiry/next_attempt用于有效性与重试；不保存正文或密钥 |
| `push_deliveries_pending` | 仅待投递的next_attempt_at索引，worker行锁SKIP LOCKED |
| `push_reminder_deadlines` | DISPATCHED/RECEIVED任务deadline部分索引，1分钟阶段窗口 |

不补推历史通知。设备注销、改密会话级联删除；投递诊断非待发记录保留30天。回滚先关闭开关，保留表及已发布迁移，不删除迁移历史。
