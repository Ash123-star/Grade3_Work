# 前端验证记录

## Flutter API client 重试与 SSE（change: flutter-api-client-resilience）

日期：2026-10-14（Asia/Shanghai）。范围为 E 负责的 Flutter API client 层收尾，不代表页面已联网或已发布。

### 本次实现

- `mobile/lib/data/repository.dart`：`HttpRepository` 的 GET（`list`/`detail`）在连接错误、连接/接收/发送超时或 HTTP 503 时重试，最多 2 次，退避 300ms、900ms；`execute`（POST 写）不自动重试，失败语义仍为 `ApiFailure`。
- `mobile/lib/core/failure.dart`：HTTP 503 从 `FailureKind.server` 修正为 `FailureKind.unavailable`（此前 `unavailable` 枚举值从未被赋值，由重试测试暴露）。
- `mobile/lib/data/sse_client.dart`：新增 `SseClient`，用 Dio `ResponseType.stream` 解析 `text/event-stream`，产出统一 `ServerEvent(event,id,data)`；通知流 `/notifications/stream` 携带并更新 `Last-Event-ID` 重连重放，AI 作业流 `/ai/jobs/{id}/stream` 收到 `event:result` 正常结束。
- `mobile/lib/core/providers.dart`：新增 `sseClientProvider`、`notificationStreamProvider`、`aiJobStreamProvider` 接入点；mock 模式返回空流，不改页面布局。
- `mobile/test/api_client_test.dart`：client 层单元测试，用可编程 Dio 适配器独立验证，不依赖真实后端。

### 实际通过

工具链：`D:\software\flutter`，Flutter 3.47.7 / channel stable / Dart 3.13.5。

- `dart analyze`：`No issues found!`。
  - 说明：`D:\software\flutter\bin\flutter.bat analyze` 的 LSP 分析服务器在本机首次运行时崩溃退出（code 255，分析服务器进程异常，非代码问题）；改用 `dart analyze` 取得干净结果。
- `D:\software\flutter\bin\flutter.bat test`：`All tests passed!`，共 26 个用例，含本次新增 `test/api_client_test.dart` 的 8 个 client 层用例，既有用例无回归。
  - 单独运行 `flutter test test/api_client_test.dart`：8/8 通过，覆盖 503 重试、瞬时连接错误重试、重试耗尽、4xx 不重试、POST 写不重试、SSE 多行解析、`Last-Event-ID` 重连游标更新、AI 流 `result` 结束。
- `openspec.cmd validate --all --strict`：本 change `change/flutter-api-client-resilience` 为 valid（唯一 failed 的 `spec/ai-map-direction-ui` 为既有占位 Purpose，与本次无关）。

改动仅限 client 层（`repository.dart`、`sse_client.dart`、`providers.dart`、`failure.dart`）与测试，未触碰后端代码、OpenAPI 契约、数据库迁移及 `mobile/lib/features/` 页面视觉。

### 实际限制

- 本次为 client 层单元测试，用可编程 Dio 适配器 Mock HTTP，未对真实后端 SSE 端点做端到端联调；真实联调属 E 后续「按模块逐个接入真实接口」阶段。
- `notification stream updates Last-Event-ID on reconnect` 用例依赖生产重连退避（当前 3 秒硬编码）；若后续将退避改为可注入，可缩短该用例等待。

## 进度与待办（2026-10-14，E）

### 已完成（本会话）
- change `flutter-api-client-resilience`：repository 重试 + sse_client + providers 接入点 + failure 503 修正 + api_client_test（8 用例）。
- 工具链 `D:\software\flutter`（Flutter 3.47.7 / Dart 3.13.5）：`dart analyze` 零问题、`flutter test` 26/26 全过、OpenSpec 严格校验 valid。
- 代码改动仍在工作区，**尚未提交/推分支**（等用户决定提交时机）。

### 待办（重启后接续）
1. **全链路真实联调回归**：环境阻塞——本机**无 Docker/PG/Redis**。用户正在安装 Docker Desktop（需 Windows 重启生效）。Docker 就绪后流程：
   - `deploy/backend/.env.example` → `.env`，填本地测试配置（勿写公开密码）。
   - `scripts/start-backend.ps1` 起后端（Compose 拉 PG16+Redis7+后端，跑 Flyway），确认 `http://127.0.0.1:8080/api/health` = UP。
   - 初始化管理员 + 强制改密 + 造联调数据。
   - Flutter 连真后端：`D:\software\flutter\bin\flutter.bat run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://127.0.0.1:8080/api`，验证登录→导图→任务/日报→通知 SSE，重点验重试与 SSE client。
   - 结果写回本文件。
   - 注：组长要求联调在全组本周增量合并齐后再做（分工文档本就安排 E 最后一天组织全链路回归），不是等 B/C/D 重写——后端已归档且集成测试通过。
2. **后端集成测试复跑**（可选但稳妥）：Docker 就绪后 `scripts/test-backend.ps1 -DockerMaven` 确认当前后端仍绿（现有证据日期为 2026-10-08~09）。
3. **提交推分支**：联调通过（或确认联调留到最后）后，按 AGENTS.md 第 4 节建 Issue → 切 `feature/<issue-id>-flutter-api-client-resilience` → 提交（带 Co-Authored-By）→ 推 → 建 PR。

### 搁置（非 E 职责）
- 导航顺序矛盾：方案第 49-50 行要求屏幕左起「我的…导图」（导图在最右），但 `mobile/lib/app.dart` 与归档变更 `android-demo-completion` 实现为左起「导图…我的」（导图在最左），两者相反。属 A 的职责，待定方向（改代码对齐方案 / 或订正方案文字对齐代码）。E 不处理。
