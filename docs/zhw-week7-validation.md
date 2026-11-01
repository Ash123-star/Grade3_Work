# 成员 E 第七周验证记录（2026-11-01）

关联 OpenSpec：`multi-founder-review`、`task-pin-and-tenure`。分支 `zhw`，基线 `origin/main` 05d6c25（PR #50）。

## 环境

- Windows 11，Docker 29.8.2，镜像 `collaboration-data-runtime:local`（PostgreSQL + Redis + Neo4j 隔离容器）。
- Flutter 位于 `D:\software\flutter`。仓库路径含中文时 analysis server 会因 JSON 编码崩溃，验收通过 `subst W:` 映射到 ASCII 路径执行。
- 基线对照：`git worktree` 检出未修改的 `origin/main`，以同样命令运行。

## 结果

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 规范 | `openspec.cmd validate --all --strict` | 47 passed, 0 failed |
| 后端定向 | `mvn test -Dtest=MultiFounderReviewIntegrationTest,TaskPinIntegrationTest,TaskDispatchIntegrationTest,ReviewIntegrationTest,ReviewPolicyTest,TaskQueryServiceTest,MobileP0MigrationUpgradeTest,MemberBPerformanceTest,OrganizationIntegrationTest,Week6AccessIntegrationTest,ScenarioDataBootstrapTest`（真实容器） | 82 run, 0 failures |
| 后端全量 | `scripts/test-backend.ps1`（最终轮） | 456 run，51 failures，2 errors；与基线相同的既有失败集合，另有 `WorkIntegrationTest.dependencyFailuresPropagateTransitivelyAndPreserveSuccessfulReceipts` 一次偶发失败，单独复跑在本分支和基线均通过（AI 办事后台任务并发干扰，与本次改动无关） |
| Flutter 分析 | `flutter analyze --no-pub lib` | 无 error/warning（6 条既有 deprecated info） |
| Flutter 定向 | `flutter test --no-pub --dart-define=USE_MOCK=true test/review_founder_peer_test.dart test/review_single_level_test.dart test/review_notification_display_test.dart test/task_pin_test.dart test/tenure_test.dart` | 全部通过 |
| Flutter 全量 | `flutter test --no-pub --dart-define=USE_MOCK=true` | 31 个失败，与基线完全相同（逐条比对，无新增） |

## 覆盖的验收场景

多创始人审核（`MultiFounderReviewIntegrationTest`、`MobileP0MigrationUpgradeTest`、`review_founder_peer_test.dart`）：
- 单创始人免审（FOUNDER_EXEMPT）保持；两位创始人时互审，申请人自审 403，管理员决定 403。
- 候选审核人排除自己；选择自己/管理员/他司/不存在用户 400 `INVALID_REVIEWER`；版本不符 409；非申请人 403；重复选择不新增步骤；原审核人改派后不能读取或决定。
- 非 FOUNDER_PEER 申请读取候选或更换审核人 409 `REVIEWER_SELECTION_UNSUPPORTED`。
- 并发：批准与更换审核人只有一个成功；同一审核人并发重复批准仅生效一次，审计与 outbox 各一条。
- 停用审核人创始人后自动改派另一位创始人并记录 `REVIEW_AUTO_REROUTED`；最后一位创始人时保持待审并发送 `REVIEW_UNASSIGNED`，管理员无法决定，申请人显式 reroute 后免审。
- 员工直属上级停用后保持待审并提醒，管理员不能决定。
- 组织变更版本冲突时不发生改派。
- V24 升级：创始人存量待审转为互审，失效步骤 SUPERSEDED，无审核人时提醒申请人和管理员，有效步骤不重复通知，已决 FOUNDER_EXEMPT 记录不变，历史候选未应用。

个人置顶与工龄（`TaskPinIntegrationTest`、`TaskQueryServiceTest`、`task_pin_test.dart`、`tenure_test.dart`）：
- 置顶优先、最近置顶在前，分页一致；同样可见的其他人排序不变；任务 version 不变、不产生审核；详情只显示本人置顶状态。
- 重复置顶返回原时间；取消未置顶成功；范围外/他司/不存在任务 404；第 11 项 409 `PIN_LIMIT`。
- 工龄：空值/未来日期“未提供”，不足一月“不满1个月”，月末与闰日边界，年月组合。

非功能：安全（越权读取与决定、自审、管理员不获得审批权、置顶不泄露他人偏好）；可靠性（并发只生效一次、通知去重、迁移可重复执行的去重键）。

## 既有失败（基线 origin/main 同样失败，非本次引入）

后端基线：443 run，50 failures，2 errors。失败集中在 `WorkIntegrationTest`（AI 办事批量/取消）、`BackendIntegrationTest`（日志首次提交窗口 FIRST_SUBMISSION_WINDOW、记忆审核状态等）、`LogSubordinateContractIntegrationTest`（当天日志重复键）、`MemberBEndToEndTest`（INVALID_VERSION）、`TaskComponentsTest.timelineOrderedBySequence`（SQL 断言过期）。本分支同一集合失败，另外两项首次全量失败（`TaskDispatchIntegrationTest` 列表字段白名单、`TaskPinIntegrationTest` 版本初值）已修复；`MemberBPerformanceTest` 首次全量 P95 超阈值，定向复跑通过，属于机器负载波动。

Flutter 基线：同样 31 个用例失败（截图/布局/标签选择器/AI 工作台等），与本分支逐条一致。

## 未完成与风险

- 未在 Android 真机或模拟器上手工走查审核详情“更换审核人”和任务表置顶按钮。
- 场景数据第二位创始人（legacy V4、annual V2）只在 SQL 层编写，未在真实场景库上执行；annual V1 只接受空库，V2 依赖 V1 已执行。
- `docs/openapi.json` 由 BackendIntegrationTest 重新生成，包含本次新增接口及运行时排序差异。
- 回滚：V24/V25 为前向迁移；回滚需手写反向脚本（删除 task_pins 表、恢复审核约束），且需先处理 FOUNDER_PEER 记录。
