# 设计：Flutter API client 重试与 SSE

## 范围与非目标

- 范围：`mobile/` 内 E 负责的 API client 层（Dio 封装、SSE 客户端、client 层 provider 接入点）。
- 非目标：不改后端、不改 OpenAPI 契约、不改 `features/` 页面视觉；不接入真实设备发布；不引第三方包。

## 边界划分

分工文档已明确：E 负责 Flutter API client（token、请求头、序列化、错误提示、超时、重试、SSE），A 明确不负责 Dio/API Client、token、接口重试、联调。因此本变更只触碰 client 数据通道（`data/repository.dart`、`core/`），页面侧仍通过稳定接口消费，与 A 无目录冲突。

## 重试策略

- 仅对幂等的 GET（`list`、`detail`）重试；`execute`（POST 写操作）即使带 `Idempotency-Key` 也不自动重试，避免客户端在不确定服务端是否已处理时放大副作用，重试交由上层用户动作触发。
- 触发条件：连接失败、连接超时、接收超时、以及 HTTP 503。4xx、409 冲突、401/403 不重试。
- 退避：最多重试 2 次，退避 300ms、900ms（指数，base 300ms）。
- 失败后抛出与现在一致的 `ApiFailure`（经 `ApiFailure.fromDio`），不改变上层错误语义。

## SSE 客户端

- 使用 Dio `GET` + `ResponseType.stream` 获取 `text/event-stream`，按 UTF-8 行解析；空行作为事件分隔，累积 `event:`/`id:`/`data:` 字段，`data:` 多行拼接。
- 产出统一的 `ServerEvent(event, id, data)` 流，供 provider 转换为页面状态。
- 通知流 `/notifications/stream`：首次用调用方传入的 `Last-Event-ID`（默认 `0`），每收到带 `id:` 的事件就更新游标；连接结束或出错后按游标重连，复用后端序号重放，避免漏/重。
- AI 作业流 `/ai/jobs/{id}/stream`：读取到 `event:result` 事件即视为完成并正常关闭，不做无限重连。
- 鉴权复用现有 `Authorization: Bearer`；重连沿用同一 token。

## 跨端契约一致性

- 事件字段名、路径、错误模型以运行时 OpenAPI 与 `docs/backend-interface.md` 为准，不新增或改写契约。
- SSE 解析格式与后端 `BackendIntegrationTest` 验证的 `event:notification`/`id:`、`event:result` 输出保持一致。

## 测试策略

- 用本地 `HttpServer`/Mock Dio adapter 独立验证：GET 重试次数与退避、503 重试、4xx 不重试、POST 不重试；SSE 多字段/多行 `data` 解析、`Last-Event-ID` 更新与重连、`event:result` 正常结束。
- client 层可独立用 Mock 验证，不依赖真实后端，满足 E 验收「API client 可独立用 Mock 验证」。
