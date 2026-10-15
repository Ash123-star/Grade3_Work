# flutter-architecture Specification

## Purpose

定义 Flutter 客户端内部目录、依赖方向和可替换 Mock 数据边界，支持后续真实后端接入。

## ADDED Requirements

### Requirement: 应用分层

Flutter 工程 SHALL 将路由、主题、核心状态、数据访问、业务页面和共享组件放在独立职责目录中。

#### Scenario: 目录职责可定位

- **WHEN** 开发者查找路由、主题、页面或数据源
- **THEN** 对应代码分别位于 `routing`、`theme`、`features` 和 `data`，无需从单一大文件中推断职责

### Requirement: Mock 与后端契约一致

Mock 数据源 SHALL 实现与未来 HTTP 数据源相同的 Repository 接口，页面 MUST NOT 直接依赖 Mock 实现或 HTTP 客户端。

#### Scenario: 切换数据源

- **WHEN** 构建配置从 Mock 切换到 HTTP
- **THEN** 页面和业务路由无需修改，只替换 Repository 提供者

### Requirement: 演示行为保持

迁移后的应用 SHALL 保留五栏导航、默认导图、加载/空数据/错误/权限状态和现有演示工作流。

#### Scenario: 迁移后运行演示

- **WHEN** 使用默认 Mock 配置启动应用
- **THEN** 五个导航入口可访问，主要页面不出现空白、异常或阻塞交互

### Requirement: 真实接入边界

本变更 MUST NOT 添加真实认证、token 持久化、后端字段适配、接口重试或真实服务调用。

#### Scenario: 网络实现未启用

- **WHEN** 使用默认构建配置运行
- **THEN** 应用只读取 Mock 数据并明确显示演示状态
