# 后端接口文档

## 通用约定

根路径为 `/api`。除公开登录、注册和健康检查外均需 `Authorization: Bearer <session-token>`。每个响应带 `X-Trace-Id`；错误体为 `{code,message,traceId}`。列表使用 `{items,total,nextCursor}`，`cursor` 为偏移量，`limit` 范围 1–100。时间使用 UTC ISO-8601，业务日期按 `Asia/Shanghai` 且周一为周首。

写请求只接受文档列出的字段。更新请求携带 `version`；创建请求可携带 `Idempotency-Key`。版本冲突返回 `409`，越权对象通常返回 `404`，明确的人员筛选越权返回 `403`。

## 认证 `/auth`

| 方法 | 路径 | 用途与权限 | 请求 | 返回/错误 |
| --- | --- | --- | --- | --- |
| GET | `/auth/departments` | 注册前读取公司部门；公开 | 无 | 部门数组；服务不可用 |
| POST | `/auth/register` | 创建待确认员工；公开；禁止 role 字段 | `account,password,phone,name,departmentId` | 员工和 membership review；400 字段/密码/手机号错误，409 重复 |
| POST | `/auth/login` | 创建会话；公开 | `account,password` | token、过期时间和用户；401 凭据错误，429 限流 |
| GET | `/auth/me` | 当前用户；已登录 | 无 | 用户公开资料；401 会话失效 |
| POST | `/auth/password` | 首次或主动改密；本人 | `oldPassword,newPassword` | `reloginRequired`；401 原密码错误，400 密码策略 |
| POST | `/auth/logout` | 撤销当前会话；本人 | 无 | `{ok:true}`；401 会话失效 |

## 组织 `/organization`

组织树和 `/people` 返回范围内数据。管理员策略、人员和组织单元的关键变更使用 `version`、`reason`，通过审核后生效。主要接口：`GET /organization`、`GET /organization/departments`、`GET /organization/people`、`POST /organization/membership-application`、`GET/POST /organization/review-policy`、`POST /organization/reviewer-application`、`POST /organization/users/{id}/revisions`、`POST /organization/{departments|teams}/revisions`、`GET /organization/audit`。

## 任务 `/tasks`

`GET /tasks` 列表故意不返回完成情况或状态列；流转事件只在 `GET /tasks/{id}` 的 `events` 中返回。`POST /tasks` 创建任务需要 `title,deadline,ownerId`，支持协作人、附件和幂等键。`POST /tasks/{id}/events` 支持 receive、feedback、accept、transfer、reschedule、withdraw；`POST /tasks/{id}/revisions` 修改已发布任务并携带版本，必要时进入审核。无派发资格返回 403。

## 日志 `/logs`

`GET /logs` 只返回本人或授权范围内已提交日志；`GET /logs/subordinates` 是下属日志入口，上级不能读取草稿。`PUT /logs/draft` 按用户和上海业务日期保存唯一草稿；`POST /logs/{id}/submit` 提交；`POST /logs/{id}/revisions` 修改已提交版本并进入审核；`GET /logs/{id}/versions`、`POST /logs/{id}/read`、`GET/POST /logs/{id}/comments` 分别用于历史、已读和评语。

## 审核 `/reviews`

`GET /reviews`、`GET /reviews/{id}` 返回申请人或当前审核步骤可见内容。`POST /reviews/{id}/decision` 请求 `{approve,reason}`，驳回时 reason 必填，申请人不能自审；`POST /reviews/{id}/reroute` 仅申请人在未决策前重建审核链。最终通过时再次校验目标版本。

## 仪表盘、通知、分析和附件

仪表盘提供 `/dashboard`、`/dashboard/company`、`/dashboard/personal`、`/profiles/{id}` 和 `/private-notes`；私人备注始终仅本人可见。通知提供 `GET /notifications`、`POST /notifications/read-all`、`POST /notifications/{id}/read` 和支持 `Last-Event-ID` 的 `/notifications/stream`。分析提供 `/analytics`、`/timeline` 和 `/analytics/export`，导出与详情使用相同数据范围。附件 `POST /attachments` 使用 multipart，单文件最大 10MB；`GET /attachments/{id}` 每次重新鉴权，不提供公开 URL。

## AI `/ai`

`POST /ai/jobs` 创建异步草稿，`GET/DELETE /ai/jobs/{id}` 查询或取消，`POST /ai/jobs/{id}/retry` 重试，`PUT /ai/jobs/{id}/draft` 按版本编辑，`GET /ai/jobs/{id}/stream` 读取 SSE，`GET /ai/usage` 查看用量。`GET /ai-maps` 和 `POST /ai-maps/edges` 管理本人范围内地图。`POST /ai/jobs/{id}/confirm-task` 必须带幂等键，确认后重新走任务派发权限和事务；AI 失败返回 job 状态，不影响普通任务和日志。

## 调用示例

```http
POST /api/tasks
Authorization: Bearer <token>
Idempotency-Key: task-20261009-001
Content-Type: application/json

{"title":"整理周报","deadline":"2026-10-10T09:00:00Z","ownerId":"user-id","body":{}}
```

```json
{"code":"VERSION_CONFLICT","message":"数据已被其他操作修改","traceId":"..."}
```
