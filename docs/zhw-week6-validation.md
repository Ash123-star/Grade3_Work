# 甄浩文 week6 客户端契约：实现与验证记录

本报告记录dc00e2b旧基线的验收。Issue #32 / Draft PR #33 的最新main整合状态见 docs/zhw-week6-main-integration.md；下方“后端尚未提供”不再代表main 808d9d6的现状。

日期：2026-10-23。分支：`zhw`，基线 `dc00e2b`。关联 OpenSpec `zhw-week6-client-contract`；远端 Issue 创建此前被拒绝，本地跟踪 `docs/issues/zhw-week6-client-contract.md`。HCJ 压缩包及解压目录仅作为前端字段参考，未合入 main。

## 已实现并验证

- 下属日志 Query 将 `departmentId` 与 `search/ownerId/date/period/cursor` 传给现有接口，分页读取保留条件；作者、部门及评论身份、回复关系在 Repository 中完整保留。
- 日志回复的 `parentCommentId` 转为后端 `parentId`；评论 POST 不自动重试。日志撤回发送 `version/reason`；24 小时能力由服务端字段与客户端时钟辅助展示，服务端仍最终校验。`LOG_EDIT_WINDOW_EXPIRED` 和 `RATE_LIMITED` 有明确文案。
- 未支持的任务 `startAt/participantIds/tagId` 和任务评论在写入前明确失败，防止静默丢字段后提交旧任务。旧任务页面继续使用 dc00e2b 的 `ownerId/collaborators` 契约；未宣称 HCJ 多参与人语义已实现。
- `scripts/e2e-smoke.ps1` 支持 PowerShell 5/7 HTTP 错误处理，检查提交能力、部门分组/组合筛选、评论回复、空内容、无效父评论、越权查询及通知入口。

## 验证证据

| 环境与命令 | 结果 | 证据 |
|---|---|---|
| Windows、JDK21、Docker 隔离数据服务；`powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven` | 退出 0；137 测试、0 失败 | `week6-backend-test.log`、`server/target/surefire-reports/` |
| 独立 `pandora-stage` 数据库、127.0.0.1:18080；`scripts/e2e-smoke.ps1` | 24 组真实 HTTP 断言通过 | `week6-smoke-final.log` |
| Flutter 3.47.7 / Dart 3.13.5；`RUN_STAGE_INTEGRATION=1`，`flutter test --no-pub test/week6_client_contract_test.dart test/member_b_error_contract_test.dart test/week6_real_backend_test.dart test/api_client_test.dart` | 退出 0；17 测试通过，含真实 Repository 日志、回复、撤回重提与权限拒绝 | `week6-verified-client.log` |
| `dart analyze lib/data/models lib/data/repositories lib/core/errors` 及本批定向测试文件 | 退出 0；No issues found | 终端结果 |
| 2026-10-23 `dart analyze`（mobile 全量） | 退出 0；No issues found | `week6-full-analysis.log` |
| `flutter test --no-pub --dart-define=USE_MOCK=true`（全量） | 退出 0；247 通过、2 跳过（真实环境开关） | `week6-mock-tests.log` |
| 默认正式模式：read_http_contract、command_http_contract、live_notifications_contract、auth_state_contract、inbox_sync_contract、member_workspace_contract、week6_client_contract、member_b_error_contract、api_client 九个文件 | 退出 0；85 项通过，包含截止时按钮自动隐藏 | `week6-formal-regression.log` |
| `openspec.cmd validate --all --strict`；PowerShell Parser 检查 smoke | 30 项通过；脚本语法无错误 | 终端结果 |
| 后端集成测试生成 `docs/openapi.json` | 与基线实际端点和字段一致，无新后端任务接口 | 文件差异检查 |

安全：真实 HTTP 验证员工不能读取下属列表、同级不能读取评论、未知部门不暴露数据；后端 137 项回归覆盖组织范围。可靠性：分页筛选不丢失、评论失败不自动重试、SSE 重连游标及 GET/POST 重试边界由 Flutter 定向测试覆盖。以上两个非功能验证均有真实或自动化证据。

## 已实现但未完成验收

- Android 设备、HCJ 合并后的页面按钮和部门选择/回复交互尚未验收。当前 zhw 页面的截止刷新已有自动化 widget 测试通过。
- SSE 的现有重连、序号去重、前后台/账号代际保护与旧账号迟到响应隔离已通过正式模式回归；尚未验证真实设备上的服务端 SSE 全链路。

## 依赖恢复与测试模式

初次分析和页面测试因本地缺少 drift 等依赖失败，历史日志保留在 `week6-flutter-test.log`。从 pub.dev 官方归档恢复 drift 2.35.2，并校验 SHA256 为锁文件中的 `ef9598e1785c18db37209e8554fc79aff94632209d384ec98984b9e3184af0f7`。

当前 Flutter 3.47.7 的 SDK 约束与原锁文件不匹配；`pub get --offline --enforce-lockfile` 明确指出 7 项必须更新，随后 `pub get --offline` 成功。`mobile/pubspec.lock` 同步 characters、intl、matcher、material_color_utilities、meta、test_api、vector_math，锁文件 Dart 下限变为 3.11.0-0。使用较旧 SDK 的成员需核对工具链与锁文件兼容性；该锁文件按本报告工具链验收。

默认 `USE_MOCK=false` 全量扫描曾得到 237 通过、2 跳过、16 失败（`week6-full-tests.log`），16 项均为依赖 Mock 初始数据的界面场景，随后显式 Mock 模式通过。正式数据/会话/SSE 场景另按上表九文件在真实模式验证。不能把 Mock 验收计入真实 HTTP 联调。

## 未完成或依赖他人

- 后端尚不接受 HCJ 所需的任务 `startAt/participantIds/tagId`、标签分类/颜色/权限和任务公开评论；相应字段回显与审核新流程没有真实联调结果。`group/progressNote/collaborators` 的旧契约仍在当前后端和旧页面中使用。
- 日志目前是窗口内**申请审核修订**，不能报告为 HCJ 的直接编辑。HCJ 页面仍有本地筛选和静态标签映射；待其合入后再核对实际交互。
- 未构造超过 24 小时的独立真实日志样本；精确边界由后端单元/集成测试和客户端模型测试覆盖。AI/DeepSeek、真机及生产环境不在本次真实验收范围。

2026-10-22 的隔离数据库与配置保留在本机 `pandora-stage`，账号材料仅存忽略的 `output/stage-demo/`。2026-10-23 检查时 Docker daemon 与 18080 服务未运行；本轮沿用上次真实证据，未声称再次执行真实后端验收。

Git 交付：按用户的提交操作，将本批已验收改动单独建立本地提交；用户预先声明的压缩包、解压目录、镜像及分工资料均排除。远端推送及 Issue/PR 状态需在执行后补充；HCJ/后端依赖继续保留为未完成项。
