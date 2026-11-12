# Proposal

## Why
Could：组内追加两个小需求，由成员 E 负责。
1. 任务管理列表（任务表单）需要“置顶”，让用户把关注的任务固定在列表最上方。当前任务没有任何置顶或排序字段，且任务的每次修改都走审核并递增版本，不适合承载显示偏好。
2. “我的”页面需要显示工龄。`users.employment_start_date` 与 `GET /profiles/me` 的 `employmentStartDate` 已存在，客户端尚未展示。

用户已确认（2026-11-01）：置顶为**个人置顶**，只影响本人列表，不走审核，不改任务版本。

## What Changes
- 新增 `task_pins` 表（Flyway，编号在 multi-founder-review 之后顺延，预计 V29）。
- 新增 `PUT /api/tasks/{id}/pin`、`DELETE /api/tasks/{id}/pin`；每人最多置顶 10 项，与导图重点一致。
- `GET /api/tasks` 列表返回 `pinned`、`pinnedAt`，服务端按“置顶优先（置顶时间倒序）→ 截止时间 → id”排序，跨页一致。
- 任务管理表行与任务详情提供置顶/取消置顶，置顶行显示图钉标记。
- “我的”头部卡片与个人资料页显示工龄（由入职日期按上海时区计算）；入职日期为空或未来显示“未提供”，其余按上海业务日期显示完整“X年X个月X天”。

非目标：日历、导图公司任务卡、已接收任务卡不按置顶排序（它们按时间语义排序）；不提供全局置顶；不允许用户自行编辑入职日期；后端不新增工龄字段。

## Capabilities
### New Capabilities
- `task-pin-and-tenure`: 个人任务置顶与工龄显示。

## Impact
- 后端：`module/task`（TaskQueryService、TaskListView、新 TaskPinService/Controller）、新迁移、OpenApi、测试。
- 移动端：`task_management_table.dart`、`task_management_page.dart`、任务详情、`dashboard_pages.dart`、`own_profile_page.dart`、`repository.dart`、`mock_repository.dart`、新工龄工具函数及测试。
- 文档：backend-interface.md、openapi.json、database-schema.md。
- 负责人：成员 E。Issue/Sprint：待关联。`task_management_*` 属成员 A 本周改动范围，需协调合并。
