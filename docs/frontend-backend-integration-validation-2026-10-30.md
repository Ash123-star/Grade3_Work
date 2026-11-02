# 前后端联调与测试记录（2026-10-30）

## 基线与范围

- 基线：`origin/main` 提交 `91908a7`，隔离工作树分支 `codex/frontend-backend-acceptance`；未改动原 `zhw` 工作树和未跟踪文件。
- 关联：Issue #40；OpenSpec `flutter-backend-contract-integration` 2.2、2.3；移动端与后端契约以当前 Controller、运行时 OpenAPI 和实际 HTTP 为准。
- 本轮在本机 Windows、Java 21、Docker 29.8.2、Flutter SDK 上执行。后端隔离容器使用 PostgreSQL 16.15、Redis 和 Neo4j。所有临时容器均使用随机名称；场景运行结束后删除自己的容器、API 进程和临时凭据文件。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| `dart analyze`（`mobile/`） | 退出 0；0 error、0 warning、8 info。`flutter analyze --no-pub` 两次以分析服务器 JSON 解析异常退出 255，不能报告该命令通过。 |
| `flutter test --no-pub --reporter expanded --concurrency=2` | 退出 1；294 通过、3 跳过、33 失败。失败分布：`week5_ui_acceptance` 6、`stage3_interaction` 5、`member_workspace_contract` 4、`stage3_supporting_ui` 4、`tuantuan_screenshot_repair` 4、`demo_ui` 3、`ai_workbench` 2，其余 5 个文件各 1。不能将全部失败视为过时断言。 |
| `powershell.exe -ExecutionPolicy Bypass -File scripts/test-backend.ps1` | 退出 1；442 项运行，49 失败、1 错误、0 跳过。`WorkIntegrationTest` 42 项（其中两组各重复 20 次）、`BackendIntegrationTest` 7 项、`MemberBEndToEndTest` 1 项。 |
| `mvn.cmd -B -f server/pom.xml -DskipTests package` | 退出 0，仅证明本轮后端可打包。 |
| 隔离数据库真实 HTTP 场景 `scripts/verify-scenario-runtime.py` | 退出 0；128/128 检查通过，涵盖登录、组织数据范围、任务审核与状态、日志、统计、附件、通知及负向权限/版本/幂等条件。 |
| 临时 Flutter `HttpRepository` 对真实隔离后端 | 退出 0；登录、任务/日志/审核读取及员工读取下属日志拒绝通过。该烟测只覆盖这些读链路，未覆盖页面操作和 Flutter 写入审批流程。 |
| 公网只读检查 | `http://39.96.84.51/api/health` 返回 200；匿名任务读取返回 401 且有 `X-Trace-Id`。云端 OpenAPI 与当前 `docs/openapi.json` 均有 148 个路径，路径集合一致。未在公网写入业务测试数据，也未登录服务器；不能据此证明部署版本及登录后链路全部通过。 |

## 失败与限制

- 后端失败涉及审核 `expectedVersion`、日志首次提交日期、AI 工作台待审结果及部分旧断言。需要逐项区分测试夹具过期与产品缺陷，不能只改断言使测试变绿。
- Flutter 33 项失败与 PR #41 记录的数量一致，但本轮使用离线 `pub get` 恢复依赖时有 7 个传递依赖被本机 SDK 重新解析。测试后已恢复版本库中的 `mobile/pubspec.lock`；若要作为发布门禁，需用锁定依赖再复核。
- 原 `week6_real_backend_test.dart` 在本轮场景种子上失败，原因是测试假定员工当天没有已提交日志，而种子已为该员工生成当日日志。此结果不构成正文编辑接口故障证据；该用例需要独立新员工或空日志夹具。临时烟测的源码与运行日志位于忽略目录，尚未纳入版本库。
- 未完成 Android 设备 UI、真实 DeepSeek/OCR、性能、无障碍、云端场景 V3 账号以及 SSH/部署状态验收。OpenSpec 2.2、2.3 保持未勾选；上述单项通过不等于整体验收完成。

## 证据与下一步

本机原始日志在忽略目录 `output/integration-20261030/`：`dart-analyze.log`、`flutter-analyze.log`、`flutter-test.log`、`backend-verify.log`、`backend-package.log`、`scenario-run.log`、`scenario-http/http-results.json`、`client-smoke-run.log` 和 `client-run.log`。临时测试脚本也在该目录；这些证据不会自动进入 PR。

1. 按后端失败测试类逐项复核当前业务契约，先处理重复 20 次的两类根因，以及审核版本、日志日期夹具；修复真实缺陷后重跑完整后端脚本。
2. 对 Flutter 33 项按文件逐项分类，先修复确认的契约和页面行为缺陷；用锁定依赖重跑全量测试和标准 `flutter analyze`。
3. 将真实 Flutter 日志写入/任务审核链路改为可重复的独立夹具测试，覆盖 UI 或稳定客户端入口到服务端与数据层，再完成 OpenSpec 2.3。
4. 设备和云端验收仅在明确目标环境及测试账号后执行，不在现有公网业务库中盲目运行写入型 smoke。
