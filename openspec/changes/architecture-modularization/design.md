# 设计

## 分层

依赖方向固定为 `api -> application -> domain`，基础设施由应用层通过端口调用：

```text
HTTP/SSE/Multipart
        |
api: Controller + Request/Response contract
        |
application: use case + transaction + orchestration
        |
domain: Actor, Scope, policy, lifecycle, validation
        |
ports: repository, notification, AI provider, clock
        |
infrastructure: JDBC/Redis/DeepSeek/SSE/outbox
```

模块只暴露应用服务或端口接口，不直接调用其他模块 Controller。跨模块协作使用 `IdentityContext`、`ScopeContext`、领域事件和只读查询端口。数据库事务由应用层用例控制；SQL、Redis key 和供应商协议留在基础设施层。

## 模块边界

| 模块 | 自有职责 | 对外暴露 |
| --- | --- | --- |
| auth | 注册、登录、会话、改密 | AuthUseCase、用户只读查询 |
| organization | 公司、部门、团队、人员、汇报链 | OrganizationUseCase、PeopleQuery |
| review | 复核链、版本、审计 | ReviewUseCase、ReviewQuery |
| task | 派发、负责人、事件、附件引用 | TaskUseCase、TaskQuery |
| log | 日报、修订、已读、评语 | LogUseCase、LogQuery |
| dashboard | 公司重点、个人重点、个人资料、私人备注 | DashboardUseCase |
| message | outbox、通知、SSE | NotificationQuery、NotificationPublisher |
| analytics | 时间范围、统计、导出 | AnalyticsQuery |
| ai | AI job、来源、地图、确认派发 | AiUseCase、AiProviderPort |
| attachment | 上传、授权下载 | AttachmentPort |

## 公共契约

公共契约只放稳定的跨模块类型：`ActorContext`、`DataScope`、`PageQuery`、`PageResult`、`ApiErrorBody`、`VersionedCommand`、`DomainEvent`。公共契约不得包含某个模块的 SQL 行、Controller 请求对象或供应商字段。

## 兼容迁移

第一阶段采用门面适配：现有类继续作为 Spring Controller，内部调用新定义的用例接口；第二阶段移动 SQL 到 repository adapter；第三阶段按模块拆文件和包。每阶段都必须通过现有集成测试和 OpenAPI 契约检查。

## 一致性规则

- 所有写操作在应用服务开启事务，并接收幂等键或版本号（适用时）。
- 所有查询先取得 `ActorContext`，再由领域 Scope 生成 SQL 条件。
- Controller 只负责 HTTP 映射、输入校验和响应映射。
- AI、通知和附件均通过端口隔离，供应商失败不能回滚普通任务/日志功能。
