# Flutter API Resilience Specification

## ADDED Requirements

### Requirement: Idempotent request retry

Flutter API client SHALL 仅对幂等的 GET 请求在瞬时失败时执行有限重试，MUST NOT 对写请求自动重试，并且 MUST 在重试耗尽后保持既有的结构化失败语义。

#### Scenario: Retry GET on transient failure

- **WHEN** GET 请求遇到连接错误、连接或接收超时、或 HTTP 503
- **THEN** 客户端最多重试 2 次，退避 300ms 与 900ms，若其中一次成功则返回该结果

#### Scenario: Do not retry client errors

- **WHEN** 请求返回 400、401、403、404 或 409
- **THEN** 客户端立即抛出对应的结构化失败，不重试

#### Scenario: Do not retry writes

- **WHEN** POST 写请求（含携带幂等键的派发）失败
- **THEN** 客户端不自动重试，直接抛出失败，由上层用户动作决定是否重发

#### Scenario: Exhausted retries

- **WHEN** GET 请求重试耗尽仍失败
- **THEN** 客户端抛出与单次失败一致的 `ApiFailure`，不改变上层错误语义

### Requirement: Server-Sent Events client

Flutter API client SHALL 提供 Server-Sent Events 客户端，解析 `text/event-stream` 并产出统一事件流，覆盖通知流与 AI 作业流，且 MUST 复用现有 Bearer 认证。

#### Scenario: Parse event stream

- **WHEN** 服务端按行发送 `event:`、`id:` 和一行或多行 `data:`，以空行分隔事件
- **THEN** 客户端将每个事件解析为包含 `event`、`id` 和拼接后 `data` 的记录并逐个产出

#### Scenario: Notification stream replay

- **WHEN** 通知流连接建立或断线重连
- **THEN** 客户端携带最近的 `Last-Event-ID`（初始为 `0`），并在收到带 `id:` 的事件后更新游标以复用服务端序号重放

#### Scenario: AI job stream completion

- **WHEN** AI 作业流收到 `event:result` 事件
- **THEN** 客户端视为完成并正常关闭流，不进行无限重连

#### Scenario: Stream failure surfaces as failure

- **WHEN** 流连接因网络或非 2xx 响应中断且无法恢复
- **THEN** 客户端以结构化失败结束流，供页面展示错误状态
