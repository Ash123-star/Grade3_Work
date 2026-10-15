# Tasks

- [x] 1. 为 `HttpRepository` 的 GET 增加幂等重试（连接/超时/503，最多 2 次，退避 300ms/900ms），写请求不重试
- [x] 2. 新增 SSE 客户端，解析 `text/event-stream` 的 `event:`/`id:`/`data:`，产出统一事件流
- [x] 3. 接入通知流 `/notifications/stream`，携带并更新 `Last-Event-ID` 支持重连重放
- [x] 4. 接入 AI 作业流 `/ai/jobs/{id}/stream`，收到 `event:result` 正常结束
- [x] 5. 在 `providers.dart` 增加流 provider 接入点，页面通过稳定接口消费，不改页面布局
- [x] 6. 增加 client 层单元测试：重试次数/退避、4xx 与写不重试、SSE 多行解析、重连游标、result 结束
- [x] 7. 执行 `flutter analyze` 与 `flutter test` 并记录结果；执行 `openspec.cmd validate --all --strict`
  - `dart analyze`：No issues found!（`flutter analyze` 的 LSP 分析服务器首次运行崩溃，改用 `dart analyze` 取得干净结果）。
  - `flutter test`：All tests passed，26 个用例（含本次新增 8 个 client 层用例，无回归）。
  - OpenSpec 严格校验通过（本 change `change/flutter-api-client-resilience` 为 valid）。
  - 工具链：D:\software\flutter，Flutter 3.47.7 / Dart 3.13.5。详见 `docs/frontend-validation.md`。
