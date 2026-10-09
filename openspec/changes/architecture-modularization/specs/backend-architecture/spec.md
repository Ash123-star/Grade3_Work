# 后端模块化架构

## Purpose

定义企业协作后端的模块边界、分层依赖和公共接口规则，使多个开发者能够在不修改其他模块内部实现的情况下协同开发。

## ADDED Requirements

### Requirement: Layered dependency
后端 SHALL 按 API、应用、领域、基础设施分层；依赖方向 SHALL 由外向内，Controller SHALL NOT 直接访问 JDBC、Redis 或 DeepSeek。

#### Scenario: Module implementation replacement
- **WHEN** 将 PostgreSQL repository 替换为测试内存 adapter
- **THEN** 应用用例和 HTTP 契约无需修改。

### Requirement: Independent module interfaces
每个业务模块 SHALL 暴露应用用例接口和必要的只读查询端口；模块 SHALL NOT 依赖其他模块 Controller 或内部 SQL 行结构。

#### Scenario: Task and notification collaboration
- **WHEN** 任务完成派发
- **THEN** 任务模块发布领域事件，消息模块通过事件端口创建 outbox，而不是被任务模块直接调用 Controller。

### Requirement: Shared contract stability
公共身份、数据范围、分页、错误、版本和事件契约 SHALL 独立于具体业务模块；已有 REST 路径、错误体和分页字段 SHALL 保持兼容。

#### Scenario: Client compatibility
- **WHEN** 移动端使用旧版分页请求访问重构后的服务
- **THEN** 服务返回相同的 `items`、`total`、`nextCursor` 和错误字段。

### Requirement: Interface documentation
每个 HTTP 接口 SHALL 注明用途、权限、请求参数、返回值、主要错误、幂等要求和版本要求；架构文档和接口文档 SHALL 与实现同步。

#### Scenario: New endpoint review
- **WHEN** 新增一个模块接口
- **THEN** 代码注释、接口文档和 OpenAPI 描述同时包含该接口的调用约束。
