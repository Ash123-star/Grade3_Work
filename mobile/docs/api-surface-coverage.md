# Mobile API Surface Coverage

更新日期：2026-10-20（Asia/Shanghai）。本表是后端联调输入，不把 Mock、静态检查或文档视为功能完成。服务器权限、组织范围和最终状态机以运行时 OpenAPI 与后端实现为准。

状态含义：

- **HTTP 已接入**：Flutter 正式模式已有明确调用，路径存在于当前 `docs/openapi.json`/Controller。
- **客户端待对齐**：页面已有字段或操作，但服务端字段/语义尚未对齐，不能报告为真实链路完成。
- **待定契约**：产品需要但后端尚未提供，客户端必须显式提示或保持 Mock，不得猜路径。
- **本地/演示**：只保存在设备或 Mock 进程，不产生企业服务写入。

| 页面/能力 | 前端操作 | 正式接口或边界 | 状态 | 后端实现输入 |
|---|---|---|---|---|
| 登录/注册/改密 | login/register/password/logout/me | `/auth/login`、`/auth/register`、`/auth/password`、`/auth/logout`、`/auth/me` | HTTP 已接入 | 认证、员工待确认、角色不能由注册参数指定 |
| 注册部门 | list | `/auth/departments` | HTTP 已接入 | 返回稳定部门 ID |
| 组织归属/复核资格申请 | membership-application/reviewer-application | `/organization/membership-application`、`/organization/reviewer-application` | 客户端待核对 | 前端表单/调用是否覆盖须逐项核对；不允许客户端直接授予角色 |
| 导图公司重点 | list/detail、request-review | `/dashboard/company`、`/dashboard/company/revisions` | HTTP 已接入 | 版本、审核、组织范围 |
| 个人重点 | list/detail/create/update/archive | `/dashboard/personal` | HTTP 已接入 | 本人范围、排序、版本 |
| 任务 | list/detail/create/events/revisions | `/tasks`、`/tasks/{id}`、`/tasks/{id}/events`、`/tasks/{id}/revisions` | 客户端待对齐 | 当前 Flutter 发 `startAt/tagId/participantIds`；服务端现有 normalizer 仍接受旧 `group/collaborators` 字段，需后端统一 DTO |
| 任务转派/改期 | transfer/reschedule | `/tasks/{id}/reassignments`、`/tasks/{id}/reschedules`（或已评审统一命令） | 客户端待对齐 | 版本、理由、审核链、幂等 |
| 任务退回补充 | return | 路径和事件枚举待定 | 待定契约 | 权限、可用阶段、原因、通知、重提 |
| 日志草稿/提交 | save-draft/submit | `PUT /logs/draft`、`POST /logs/{id}/submit` | HTTP 已接入 | 业务日唯一、版本冲突、首次提交时间 |
| 已提交日志 24h 修改 | update | 当前无正式直改路径 | 待定契约 | 服务端提交成功起算 24h、越界拒绝、并发/版本规则 |
| 日志候选修订 | request-review | `POST /logs/{id}/revisions` | HTTP 已接入 | 审核链、自审拒绝、旧版持续有效 |
| 下属日志 | list/detail | `GET /logs/subordinates`、`GET /logs/{id}` | HTTP 已接入 | 服务端先鉴权再按 owner/date 查询 |
| 日志已读登记 | read | `POST /logs/{id}/read` | HTTP 已接入 | 只允许已提交且在可见范围 |
| 阅读人员清单 | read-roster | 路径待定 | 待定契约 | 最小字段、分页、草稿/越权拒绝 |
| 日志评论 | list/comment | `GET/POST /logs/{id}/comments` | HTTP 已接入（普通评论） | 当前服务端只接 `text` |
| 评论回复/任务评论 | reply、tasks/comments | 当前无服务端路径/字段 | 待定契约或 Mock-only | `parentCommentId`、作者、权限、不可编辑删除 |
| 审批 | list/detail/approve/reject/reroute | `/reviews`、`/reviews/{id}`、`/reviews/{id}/decision`、`/reviews/{id}/reroute` | HTTP 已接入 | 自审拒绝、驳回原因、版本 |
| 组织/成员/策略 | tree/list/profile/revisions | `/organization`、`/organization/people`、`/profiles/{id}`、组织 revisions | HTTP 已接入 | 公司范围、管理员、版本和审核 |
| 组织部门 | list | `GET /organization/departments` | HTTP 已接入 | 团队层级由服务端字段明确返回；OpenAPI 当前没有独立 `GET /organization/teams` |
| 组织团队单独列表 | list | 当前无独立列表路径 | 待定契约 | 未登记的 `organization/teams` 已由 HTTP adapter 阻断，不自动请求猜测路径 |
| 角色/成员归属/直属上级/停用 | revise | `POST /organization/users/{id}/revisions` | HTTP 已接入或待核对具体表单 action | 字段按用户修改集提交；缺少接口调用的表单 action 必须在后续专项适配，不以共用 URL 存在推断完成 |
| 通知 | list/read/read-all/stream | `/notifications`、`/notifications/{id}/read`、`/notifications/read-all`、`/notifications/stream` | HTTP 已接入 | SSE Last-Event-ID、outbox、去重 |
| 附件 | upload/download | `POST /attachments`、`GET /attachments/{id}` | HTTP 已接入 | 1B–10MB、权限、文件名安全；删除未提供 |
| 统计/导出 | summary/export | `/analytics`、`/analytics/export` | HTTP 已接入 | 统计与导出同权限范围 |
| AI 作业 | create/get/cancel/retry/draft/stream/confirm/usage | `/ai/jobs*`、`/ai/usage` | HTTP 已接入但有并发缺口 | 范围由服务端 Actor；confirm 缺 job version 原子前置条件 |
| AI 范围选择 | scope | 现有创建接口未提供正式 scope 参数 | 待定契约 | 角色允许范围取交集，来源重验，敏感数据隔离 |
| AI 地图 | list/edge | `/ai-maps`、`/ai-maps/edges` | HTTP 已接入 | 禁止自身依赖、来源授权 |
| AI 发展关系分析 | list/create/get/retry/evidence/feedback/stream | `/ai-maps/development`、`/ai-maps/development/jobs`、`/ai-maps/development/jobs/{id}`、`/ai-maps/development/{id}/evidence`、`/ai-maps/development/{id}/feedback` | HTTP 已接入 | 权限范围和模型密钥由服务端负责；Mock 关系图不作为真实分析结果 |
| 长期记忆 | list/create/revise/confirm/delete | `/ai-memories`、`/ai-memories/{id}/revisions`、`/ai-memories/{id}/confirm`、`/ai-memories/{id}` | HTTP 已接入 | 记忆来源、scope、审核/删除和敏感字段约束 |
| 长期记忆索引/偏好 | status/preferences/rebuild/backfill/forget/retry | `/ai-memories/knowledge-status`、`/ai-memories/preferences/me`、`/ai-memories/index-rebuild*`、`/ai-memories/backfill`、`/ai-memories/forget-jobs/{id}` | HTTP 已接入/逐操作核对 | 管理权限、幂等、后台任务失败重试与结果读取 |
| 我的反馈 | list/detail/submit/progress | 当前无 feedback Controller | 待定契约 | 本人范围、状态、附件、分页、错误码 |
| 标签字典 | list/create/revise/archive | 当前没有稳定标签字典查询/维护契约 | 待定契约 | 当前 UI 静态标签不能作为稳定 tagId 字典 |
| 本地草稿/安全会话 | save/read/clear | 本机 Drift/安全存储 | 本地/演示 | 不上传密码/API Key；设备安全能力需单独验收 |
| 页面装饰/柴犬素材 | load asset | Flutter bundle | 本地/演示 | 不产生后端接口，不承担状态语义 |

## 接入规则

1. 后端实现以本表的“前端操作”作为业务语义输入，再冻结路径、DTO、错误码、分页、权限、幂等和版本条件。
2. 新接口必须同步运行时 SpringDoc、`docs/openapi.json`、后端接口文档、Flutter Repository 和契约测试。
3. 未定契约的正式模式只能显示明确的“待接入/不可用”状态；Mock 行为只能用于演示。
4. 客户端过滤不构成安全边界；所有数据范围、角色和状态转换由服务端校验。
