# 前端接口草案

本契约用于 UI 框架接入，尚非已经上线的服务。所有请求使用 HTTPS；认证后附加 Bearer token，服务端再次验证 company_id、角色和对象范围。客户端不接收 DeepSeek 密钥。

## 通用协议

GET /{resource} 接收 search、cursor、limit、ownerId、from、to，返回 `{items: Record[], total, nextCursor}`。时间为 UTC ISO8601，from 包含、to 不包含；业务时区 Asia/Shanghai，周一为周首。

GET /{resource}/{id} 返回 Record。Record 包含 id、title、subtitle、ownerId、version、fields。fields 是本阶段 UI 聚合展示数据；接后端时在 data 层映射成正式领域 DTO，widget 不解析 HTTP JSON。

POST /{resource} 接收 `{action, values, version?}`，修改命令在 values 中带 id。创建和提交请求可携带 Idempotency-Key；重要修改携带当前 version。响应为 Record；审批响应应同时区分生效版本和候选版本。服务端返回 409 时客户端保留输入、提示刷新，不能盲目覆盖。

统一失败覆盖 400/422 表单校验、401 登录失效、403 无权限、404 不存在、409 版本冲突、超时与 5xx；响应头可带 x-trace-id。错误日志不得记录密码、访问令牌、私人备注和 AI 密钥。

## 页面与接口

| 页面入口 | resource | action / 行为 |
| --- | --- | --- |
| /form/login、register、password | auth | login/register/password，注册不允许 role 参数 |
| 导图公司重点 | dashboard/company | 只读列表；独立 publish 入口 request-review |
| 个人重点 | dashboard/personal | create/update/archive，排序由字段传递 |
| /form/note | private-notes | save，服务端仅返回本人备注 |
| /list/tasks、任务详情 | tasks | create/receive/feedback/accept/transfer/reschedule/withdraw |
| 日志和时间视图 | logs | submit/request-review，user+businessDate 唯一 |
| 下属日志 | logs/subordinates | ownerId 限于管理范围 |
| 评语和历史 | logs/comments、logs/{id}/versions | comment；历史接口待按服务端映射 |
| 审批中心 | reviews | approve/reject，自审禁止，reject reason 必填 |
| 组织和管理页面 | organization、organization/admin | 部门、归属、角色、汇报关系、停用、策略 |
| 消息 | notifications | read-all；详情按业务对象跳转 |
| 分析、导出 | analytics、analytics/export | 当前区间和范围，导出结果不得越权 |
| AI 地图 | ai-maps、ai | summarize，建议包含来源和生成时间 |

任务表单必填 title、deadline、ownerId；仅一个主负责人。派发页不显示完成情况字段，流转事件放到详情。API 日期字段转换使用 UTC，显示采用业务日期。

## 待接入的异步边界

附件目前只选择本地文件名。生产接入建议 POST /attachments 获取受控上传凭证，返回附件 ID，再由业务提交引用；下载时重新鉴权。当前不宣称附件已上传。

SSE 建议 GET /notifications/stream，事件携带 id、type、objectId，支持 Last-Event-ID 重连；由后端事务 outbox 保证最终投递，客户端按事件 ID 去重并刷新未读数。当前 UI 使用 repository 拉取，SSE 消费器属于服务接入阶段。

AI 建议 POST /ai/jobs、GET /ai/jobs/{id}、DELETE /ai/jobs/{id}，取消与限额由服务端确认。当前演示取消只阻止过期结果更新 UI，不能假称取消了远程模型请求。导出建议使用异步 job 和短期下载 URL，当前演示不生成真实下载文件。

## 界面范围

五栏：/profile、/ai、/logs、/calendar、/dashboard。辅助路由：/list/:resource、/item/:resource/:id、/form/:kind、/settings、/admin、/pending、/disabled、/expired、/privacy、/licenses、/history、/conflict、/report、/ai-usage、/export。具体表单由 features/catalog.dart 维护。
