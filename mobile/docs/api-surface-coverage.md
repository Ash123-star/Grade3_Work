# 页面与请求映射

本表只用于查找页面对应请求，不重复维护“已完成/缺失/待验”清单。状态与验收统一见 [接口接入](../../docs/backend-interface-gaps.md)，字段/错误/权限以 [后端契约](../../docs/backend-interface.md)、Controller及OpenAPI为准；路径简写以`/api`为前缀，通配符不是新增URL授权。

| 页面/能力 | 操作 | 请求或边界 | 接入注意 |
| --- | --- | --- | --- |
| 登录/注册/改密 | login/register/password/logout/me | `/auth/login`、`/auth/register`、`/auth/password`、`/auth/logout`、`/auth/me` | 认证、员工待确认、角色不能由注册参数指定 |
| 注册部门 | list | `/auth/departments` | 返回稳定部门 ID |
| 组织归属/复核资格申请 | membership-application/reviewer-application | `/organization/membership-application`、`/organization/reviewer-application` | 前端表单/调用是否覆盖须逐项核对；不允许客户端直接授予角色 |
| 首页事件纪/公司重点 | list/detail、request-review | `/dashboard/company`、`/dashboard/company/revisions` | 版本、审核、组织范围 |
| 个人重点 | list/detail/create/update/archive | `/dashboard/personal` | 本人范围、排序、版本 |
| 任务 | list/detail/create/events/revisions | `/tasks`、`/tasks/{id}`、events/revisions | 字段/多标签/参与人按现行任务DTO映射，派发表单无完成情况 |
| 任务转派/改期 | transfer/reschedule | `/tasks/{id}/reassignments`、`/tasks/{id}/reschedules`（或已评审统一命令） | 版本、理由、审核链、幂等 |
| 任务退回补充 | return | POST /tasks/{id}/events RETURNED，version/text | FEEDBACK→RECEIVED，派发人/管理员，事件/outbox |
| 日志草稿/提交 | save-draft/submit | `PUT /logs/draft`、`POST /logs/{id}/submit` | 业务日唯一、版本冲突、首次提交时间 |
| 已提交日志 24h 修改 | update | `PUT /logs/{id}/content` | 作者/首次提交24h/version；旧修订/撤回不能绕过 |
| 下属日志 | list/detail | `GET /logs/subordinates`、`GET /logs/{id}` | 服务端先鉴权再按 owner/date 查询 |
| 日志评论 | list/comment | `GET/POST /logs/{id}/comments` | 当前服务端只接 `text` |
| 评论回复/任务评论 | reply、tasks/comments | `GET/POST /tasks/{id}/comments`、`/logs/{id}/comments` | parentId同对象；任务写入需幂等键，日志写入不盲重试 |
| 审批 | list/detail/approve/reject/reroute | `/reviews`、`/reviews/{id}`、`/reviews/{id}/decision`、`/reviews/{id}/reroute` | 自审拒绝、驳回原因、版本 |
| 组织/成员/策略 | tree/list/profile/revisions | `/organization`、`/organization/people`、`/profiles/{id}`、组织 revisions | 公司范围、管理员、版本和审核 |
| 组织部门 | list | `GET /organization/departments` | 按组织范围 |
| 组织团队单独列表 | list | GET /organization/teams | 沿用当前组织树范围，不扩大人员权限 |
| 角色/成员归属/直属上级/停用 | revise | `POST /organization/users/{id}/revisions` | 字段按用户修改集提交；缺少接口调用的表单 action 必须在后续专项适配，不以共用 URL 存在推断完成 |
| 通知 | list/read/read-all/stream | `/notifications`、`/notifications/{id}/read`、`/notifications/read-all`、`/notifications/stream` | SSE Last-Event-ID、outbox、去重 |
| 附件 | upload/download | `POST /attachments`、`GET /attachments/{id}` | 1B–10MB、权限、文件名安全；删除未提供 |
| 统计/导出 | summary/export | `/analytics`、`/analytics/export` | 统计与导出同权限范围 |
| AI 作业 | create/get/cancel/retry/draft/stream/confirm/usage | `/ai/jobs*`、`/ai/usage` | scope、确认作业version/actionIndex/task与幂等键；服务端重验来源 |
| AI 范围选择 | scope SELF/AUTHORIZED | POST /ai/jobs，默认AUTHORIZED，worker/retry保持 | 当前权限上限、失权与后台一致性 |
| AI 地图 | list/edge | `/ai-maps`、`/ai-maps/edges` | 禁止自身依赖、来源授权 |
| AI 发展关系分析 | list/create/get/retry/evidence/feedback/stream | `/ai-maps/development`、`/ai-maps/development/jobs`、`/ai-maps/development/jobs/{id}`、`/ai-maps/development/{id}/evidence`、`/ai-maps/development/{id}/feedback` | 权限范围和模型密钥由服务端负责；Mock 关系图不作为真实分析结果 |
| 长期记忆 | list/create/revise/confirm/delete | `/ai-memories`、`/ai-memories/{id}/revisions`、`/ai-memories/{id}/confirm`、`/ai-memories/{id}` | 记忆来源、scope、审核/删除和敏感字段约束 |
| 长期记忆索引/偏好 | status/preferences/rebuild/backfill/forget/retry | `/ai-memories/knowledge-status`、`/ai-memories/preferences/me`、`/ai-memories/index-rebuild*`、`/ai-memories/backfill`、`/ai-memories/forget-jobs/{id}` | 管理权限、幂等、后台任务失败重试与结果读取 |
| 意见反馈 | 已移除 | 用户取消；移动端表单/入口/Mock支持删除，旧深链回帮助页 | 不新增服务 |
| 标签字典 | list/create/revise/archive | `/task-labels`及现行维护路径 | 权限/审核/版本遵循正式契约；不把静态标签作为服务端字典 |
| 本地草稿/安全会话 | save/read/clear | 本机 Drift/安全存储 | 不上传密码/API Key；设备安全能力需单独验收 |

意见反馈与日志阅读登记/人员清单已停用，不按旧表恢复。组织归属、审核资格或用户变更表单须逐操作核对Repository和正式接口，不能凭URL存在报告页面完成。AI办事新工作台的事项、文件、检查与授权映射见 [办事API](../../docs/ai-work-assistant-api.md)，不与旧分析作业混用。个人事项走 [独立todo接口](../../docs/personal-todos-interface.md)。

Repository承担协议映射；公共接口变更同步SpringDoc/OpenAPI、文档和契约测试。客户端guard/过滤不构成权限边界；HTTP失败不回退Mock成功；本地安全存储与素材不是企业后端接口。
