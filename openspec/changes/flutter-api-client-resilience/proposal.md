# Flutter API client 重试与 SSE 收尾

## Why

E 负责的 Flutter API client 层已经具备 token、请求头、序列化、超时和错误映射（`mobile/lib/data/repository.dart`、`mobile/lib/core/failure.dart`），但 MVP 分工（`docs/mvp-team-division.md`）要求的「超时、重试和 SSE 客户端」仍有两处缺口：

- `HttpRepository` 对瞬时失败（连接/超时/503）没有有限重试，联调时偶发网络抖动会直接报错。
- 后端已存在并通过集成测试的两条 Server-Sent Events 端点 `/notifications/stream`（带 `Last-Event-ID` 重放）和 `/ai/jobs/{id}/stream`，Flutter 侧没有任何 SSE 客户端，页面无法接收通知刷新和 AI 流式结果。

后端契约和这两条端点已稳定（见 `docs/backend-validation.md`、`BackendIntegrationTest` 第 7、8 条），本变更只补客户端 client 层，不改后端，也不改页面视觉。

## What Changes

- 为 `HttpRepository` 增加幂等请求的有限重试：仅 GET 在连接错误、超时或 503 时重试，最多 2 次，指数退避 300ms/900ms；4xx、业务冲突和非幂等写请求不重试。
- 新增 SSE 客户端，使用 Dio `ResponseType.stream` 解析 `text/event-stream`，按行解析 `event:`/`id:`/`data:` 字段，与后端输出格式对齐。
- 通知流携带并在重连时更新 `Last-Event-ID` 以复用后端序号重放；AI 作业流读取到 `event:result` 后正常结束。
- 提供可被 `providers.dart` 消费的流接口和稳定的失败类型，页面通过稳定状态接口接入，不改页面布局。
- 增加 client 层单元测试，用本地 Mock HTTP 独立验证重试次数、不该重试的场景、SSE 解析与断线重连。

## Capabilities

### New Capabilities

- `flutter-api-resilience`: Flutter API client 的幂等重试策略与 Server-Sent Events 客户端，面向通知流和 AI 作业流，提供稳定的流接口和失败语义。

### Modified Capabilities

- 无。既有 `frontend-api-contracts` 的请求/响应模型、路径和错误模型保持不变，本变更只增强 client 的失败处理与流式能力。

## Impact

- 影响 `mobile/lib/data/repository.dart`、`mobile/lib/data/sse_client.dart`（新增 SSE client）、`mobile/lib/core/providers.dart`（新增流 provider 接入点）。
- 修正 `mobile/lib/core/failure.dart`：HTTP 503 从 `FailureKind.server` 归类为 `FailureKind.unavailable`，使重试耗尽后的失败语义准确（此前 `unavailable` 枚举值从未被赋值，由本次重试测试暴露）。
- 不改后端代码、OpenAPI 契约、数据库迁移，也不改 `mobile/lib/features/` 页面视觉与交互。
- 不引入新的第三方依赖，复用现有 Dio。
- 需要可执行 `flutter analyze` 和 `flutter test`。
