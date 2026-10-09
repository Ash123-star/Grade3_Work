# 后端架构设计

## 目标

后端为 Flutter Android 和 Web 管理端提供同一套 REST/SSE 服务。架构围绕企业、部门、团队、人员和数据范围组织，保证任务、日报、审核、通知和 AI 功能可以独立演进。

## 分层与依赖

```text
客户端
  -> api（Controller、HTTP DTO、JavaDoc、错误映射）
  -> application（用例、事务、幂等、跨模块编排）
  -> domain（角色、数据范围、生命周期、审核规则）
  -> ports（Repository、EventPublisher、AiProvider、Clock）
  -> infrastructure（JDBC/Flyway、Redis、DeepSeek、Outbox、SSE）
```

API 层负责 HTTP 映射；应用服务承载事务、调度和跨模块用例；领域/规则层承载权限与状态约束；基础设施层承载 JDBC、Redis、SSE 和 DeepSeek 适配。公共契约位于 `cn.workpanel.contract`，通用能力位于 `cn.workpanel.shared`，业务模块位于 `cn.workpanel.module`。旧版根包 Controller 已迁移并删除，HTTP 路径保持稳定但不保留旧类名兼容层。

## 当前 Java 包骨架

```text
cn.workpanel
├── shared
│   ├── api              # PageResponse、ErrorResponse、VersionCommand
│   ├── application      # UseCase 标记
│   ├── domain           # DomainEventPublisher
│   └── infrastructure   # RepositoryPort
├── contract             # ActorContext、DomainEvent、分页和版本契约
└── module
    ├── auth             # api / application / controller / dto
    ├── organization     # api / controller / dto
    ├── task             # api / application / domain / infrastructure / controller / dto
    ├── log              # api / application / controller / dto
    ├── review           # api / application / controller / dto
    ├── message          # api / application / controller / dto
    ├── analytics        # api / controller / dto
    ├── ai               # api / controller / dto
    └── attachment       # api / controller / dto
```

每个模块的 `api` 是对外应用边界，`controller` 负责 HTTP 映射，`application` 负责事务和用例编排，`domain` 负责业务规则，`infrastructure` 负责数据库和外部适配，`dto` 负责请求/响应模型。当前已建立包和接口骨架；旧平面 Controller 的真实迁移仍需逐模块完成。

## 功能模块

| 模块 | 责任 | 主要数据 | 对外端口 |
| --- | --- | --- | --- |
| auth | 注册、登录、会话、改密、初始化管理员 | users、sessions | AuthUseCase |
| organization | 组织树、人员、汇报关系、范围 | companies、departments、teams、reporting_relations | OrganizationUseCase、PeopleQuery |
| review | 候选版本、审核链、审计、冲突 | review_requests、review_steps、audit_records | ReviewApplication |
| task | 派发、接收、反馈、验收、转派、撤回 | tasks、task_assignees、task_events | TaskApplication |
| log | 每日草稿、提交、修订、已读、评语 | daily_logs、log_versions、log_reads、log_comments | LogApplication |
| dashboard | 公司重点、个人重点、资料和私人备注 | dashboard_items、private_notes、users.profile | DashboardUseCase |
| message | outbox、通知、提醒、SSE 重放 | outbox_events、notifications | NotificationPublisher、NotificationQuery |
| analytics | 时间范围、统计、CSV 导出 | 任务/日志事件投影 | AnalyticsQuery |
| ai | DeepSeek job、来源、地图、确认任务 | ai_jobs、ai_map_nodes、ai_map_edges | AiApplication、AiProviderPort |
| attachment | 上传、授权下载、任务附件 | attachments | AttachmentPort |

## 公共契约

`ActorContext` 表示经过认证的权限快照；`PageQuery/PageResult` 统一分页；`VersionedCommand` 统一版本和幂等键；`DomainEvent` 作为跨模块异步协作载体。公共类型不暴露数据库行、HTTP 请求对象、密码、手机号或 DeepSeek 字段。

## 一致性和安全

- 所有读写先校验公司和数据范围，统计、导出、附件和 AI 使用同一范围规则。
- 关键修改携带版本号，冲突返回 `409 VERSION_CONFLICT`。
- 创建任务、通知 outbox 和审计在同一事务中提交；通知投递失败不回滚业务。
- AI 输入由服务端过滤，结果始终是带来源的草稿；确认后才进入普通任务用例。
- 会话、限流和 AI 预算使用 Redis；持久业务数据只使用后端 Flyway 模型。

## 分阶段迁移

1. 已完成：保留现有 Controller 和数据库，建立 `shared`、`contract` 和 `module/*` 包骨架与接口注释。
2. 下一阶段：先迁移任务模块，提取可运行的 `TaskController`、`TaskApplicationService`、领域规则、DTO 和 JDBC Repository，保持 `/api/tasks` 兼容。
3. 后续迁移日志、审核、组织、消息、分析、AI 和附件模块；每个模块必须有真实调用链和对应测试。
4. 稳定阶段：删除或降级旧平面类，使用 OpenAPI、包依赖检查和集成测试锁定公共契约。

当前实现已完成 Controller 入口的模块分包和主要用例服务迁移：任务、日志、审核、组织、认证、通知、AI、分析、附件和仪表盘均从 `cn.workpanel.module.*` 暴露。数据库仍使用统一 `Db` JDBC 适配器，业务范围规则由 `Business` 集中提供；模块应用边界位于各模块 `api/application` 包，HTTP 适配器不再使用根包 Controller。编译和集成测试结果以验证记录为准，不以文件骨架代替功能验收。
