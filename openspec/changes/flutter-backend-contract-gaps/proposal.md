# Proposal

## Why

Flutter 页面已经接入现有 Spring Boot Controller 和运行时 OpenAPI，但“我的反馈”资源仍可能通过通用映射请求后端不存在的路径，且产品要求中的退回补充、日志阅读人员清单和部分 AI 并发/范围能力尚未形成可交付契约。现在记录并拆分这些缺口，可以让小组后续按接口负责人补齐，避免客户端继续猜测路径或把 Mock 行为当作真实能力。

## What Changes

- 建立后端接口缺口清单，记录当前客户端可能触发的 `GET /feedback`、`GET /feedback/{id}` 未实现请求。
- 为意见反馈建立后续查询、提交、处理进度和附件策略的契约设计入口。
- 为任务退回补充建立权限、状态、原因、事件、通知和版本语义的契约设计入口。
- 为日报阅读人员清单建立授权查询、分页和隐私边界的契约设计入口。
- 为 AI 作业建立服务端范围筛选和 Actor 权限交集规则。
- 为 AI 确认任务建立 job 版本前置条件、幂等和原子事务规则。
- 同步后端接口文档、Flutter 接口交接文档、本地 Issue 和阶段3未完成任务。

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `collaboration-backend`: 补充反馈、任务补充流转、日志阅读清单和 AI 范围/版本确认要求。

## Impact

- 影响 `server` 的任务、日志、AI、反馈相关 Controller/application/domain/infrastructure 及可能的 Flyway 迁移。
- 影响 SpringDoc/OpenAPI、`docs/backend-interface.md`、`docs/openapi.json` 和 Flutter 的 `HttpRepository`/AI 数据源。
- 影响真实 PostgreSQL/Redis 集成测试、Flutter 正式 HTTP 契约测试和权限/并发验收。
- 本变更只建立规划与契约边界；具体 URL、DTO、表结构和状态枚举须经设计评审后确定。
