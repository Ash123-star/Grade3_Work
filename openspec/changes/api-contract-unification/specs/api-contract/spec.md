# API Contract Specification

## ADDED Requirements

### Requirement: Unified task event contract

任务事件接口 SHALL 接受统一的事件枚举、版本字段和事件专用字段，并按当前用户的数据范围执行授权。

#### Scenario: Transfer task

- **WHEN** 有派发权限的用户提交 `type=TRANSFERRED`、有效 `ownerId` 和当前 `version`
- **THEN** 任务负责人更新、版本递增并追加事件时间线

#### Scenario: Reschedule task

- **WHEN** 有派发权限的用户提交 `type=RESCHEDULED`、未来的 `deadline` 和当前 `version`
- **THEN** 任务截止时间更新、版本递增并追加事件时间线

#### Scenario: Invalid event payload

- **WHEN** 事件类型、负责人、截止时间或版本不满足契约
- **THEN** 服务端返回结构化错误，任务数据和版本保持不变

### Requirement: Contract documentation consistency

静态 OpenAPI、接口文档和运行时 Controller SHALL 对每个公开接口使用相同的路径、HTTP 方法、请求字段、枚举和错误模型。

#### Scenario: Client integration

- **WHEN** 客户端依据静态 OpenAPI 发送合法请求
- **THEN** Spring Boot 路由能够匹配并返回文档声明的响应或结构化错误
