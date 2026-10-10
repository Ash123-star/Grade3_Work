# 统一后端 API 契约

## Why

静态 OpenAPI、接口说明和 Spring Boot Controller 的路径基本一致，但任务事件、请求字段和文档语义存在漂移，前后端无法据此稳定联调。

## What Changes

- 以当前 SpringDoc 运行时契约和 Controller 行为作为唯一实现基准。
- 补齐任务转派、改期事件，并统一任务事件枚举、字段和权限说明。
- 同步 OpenAPI 配置、静态 OpenAPI 文件和后端接口文档。
- 增加契约一致性验收和联调示例。

## Impact

- 影响任务事件接口 `/api/tasks/{id}/events`。
- 不改变既有 URL 前缀、认证方式、分页结构和数据库迁移历史。
- 客户端需要按统一事件枚举发送请求。
