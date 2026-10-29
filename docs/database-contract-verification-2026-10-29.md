# 数据库与前端契约验收（2026-10-29）

## 结论与范围

已核对当前移动端请求、服务端读写与 `server` Flyway 模型。V22/V23 提供本批所需结构；无需另增重复字段或使用 `deploy/postgresql` 模型。独立本地数据库已实际升级到 V23，不代表其他环境已经更新。用户明确回复“不用”同步实际开发数据库。

当前分支 HCJ 存在大量用户及其他模型的混合改动；本批保留这些改动，未提交、推送或创建 PR。本次集中验收已获用户授权，取代此前“实现期间不测试”的限制。

## 数据匹配

| 前端数据 | 数据库存储与实际验证 |
|---|---|
| 手机、邮箱、性别、年龄、入职日 | `users.phone/email/gender/age/employment_start_date`；手机号保留唯一约束并允许清空，年龄非负；历史无可靠入职日保持 NULL，不推算日期 |
| 简介、头像 | 保留 `users.profile` JSONB；资料更新保留未修改字段，结构化列优先；HTTP 验证清空、版本冲突、手机号重复、联系方式上下级权限 |
| 审核模式与决定来源 | V22 的 `approval_mode/decision_source/SUPERSEDED`；历史待审步骤重路由，不批量执行候选；直属单级审核，成员确认保留管理员规则 |
| 任务参与人、起止时间、成果附件、评论 | 复用既有 `task_participants/start_at/deadline/task_events` 及附件/评论关系；无需重复新增列；HTTP 验证退回、补充附件、重交、验收、事件与授权下载 |
| 日志月状态、范围、正文编辑 | 复用 `daily_logs`、首次提交时间与入职日；既有下属日志 HTTP 契约用例通过 |
| AI 范围 | `ai_jobs.input.scope` 持久化 SELF/AUTHORIZED，默认 AUTHORIZED；测试确认来源、候选人员与统计范围一致 |
| AI 确认版本与重试 | V23 `ai_task_confirmations`；同公司/所有者复合外键、唯一回执、版本及行动索引约束；验证旧版本无写入、并发同键只创建一次、同键异内容拒绝及编辑后重放 |

AI 工作台复用 TaskApi 时发现真实契约错误：创建返回审核申请，但旧调用读取任务 version 并把审核 ID 当任务 ID。已修复为待审返回 reviewId、WAITING_REVIEW，创始人批准后才获取真实任务。交付候选与授权改为当前 task_participants/PARTICIPANT。审核结果轮询跳过仍待审申请，避免其占满批次。新增真实 HTTP 回归覆盖创建申请到直属上级批准、作业成功以及唯一回执。

移动端修复 `detail_pages.dart` 的缺失方法右括号和重复状态字段，修复路由条件块及冗余空断言。未弱化生产输入或权限校验以适配旧测试。

## 环境与迁移证据

- Windows、JDK 21、Maven；Flutter 3.38.7 / Dart 3.10.7。
- 本机无 Docker，标准 `scripts/test-backend.ps1` 无法在此环境执行；替代使用 WSL Ubuntu 的真实 PostgreSQL 18.6、Redis 8.0.5 及 Maven，不宣称标准容器脚本通过。Neo4j/真实模型、OCR 服务未验收。
- 独立库 `workpanel_acceptance_007372c8`，专用随机凭据仅放在被忽略的 `output/db-contract-20261029/environment.json`，不写入本报告或提交。
- Spring Boot 实际执行空库 V1→V23。迁移用例在独立随机 schema 验证 V21→V22 的资料/历史审核保留，以及 V22→V23 的 AI 历史作业、外键、唯一性和无效值拒绝。Flyway 历史查询确认 V21、V22、V23 success=true，字段元数据与上表一致。
- Flyway 提示 PostgreSQL 18 比其已测试最高版本 17 新；本次结果不能替代部署镜像版本的兼容性验收。

## 命令和结果

日志均位于本地被忽略的 `output/db-contract-20261029/`。运行 Maven 前，按该目录环境文件设置同名进程环境变量，不输出密码。

| 检查 | 结果及日志 |
|---|---|
| `mvn.cmd -B -f server/pom.xml -DskipTests package` | 最终退出 0；`backend-package-final.log` |
| `mvn.cmd -B -f server/pom.xml -Dtest=WorkIntegrationTest#taskCreationReceiptUsesReviewIdUntilManagerApproval,MobileDataContractIntegrationTest,MobileP0MigrationUpgradeTest,TaskQueryServiceTest,LogQueryServiceTest,LogWorkflowServiceTest,ReviewPolicyTest,LogSubordinateContractIntegrationTest test` | 最终 41 项全部通过，退出 0；`backend-contract-final2.log` |
| `mvn.cmd -B -f server/pom.xml verify` | 全量执行 425 项，139 失败、21 错误，退出 1；`backend-verify-2.log`。这是修复前结果，不能由定向通过推断最终全量通过 |
| 后端扩展定向组（含 TaskDispatchIntegrationTest） | 中间执行 67 项、4 失败，退出 1；`backend-contract-2.log`。工作台新增用例随后修复并通过；TaskDispatch 仍有 3 个旧契约失败待更新和复核 |
| `flutter analyze --no-pub`（mobile） | 退出 0，No issues found；`flutter-analyze-2.log` |
| `flutter build apk --release --no-pub --dart-define=USE_MOCK=false`（mobile） | 退出 0，正式接口模式 APK 115.9 MB；`flutter-build.log`；产物 `mobile/build/app/outputs/flutter-apk/app-release.apk` |
| `flutter test --no-pub --reporter expanded test/ai_http_workflow_test.dart test/api_client_test.dart test/subordinate_log_range_http_test.dart test/task_interval_http_test.dart`（mobile） | 35 项通过，退出 0；`flutter-contract-final.log` |
| `flutter test --no-pub --reporter expanded`（mobile） | 最终 281 通过、3 跳过、44 失败，退出 1；`flutter-test-final.log` |
| `npm ci --prefer-offline --fetch-retries=0` 后 `npm run build`（web） | 两者退出 0；`web-install-final.log`、`web-build-final.log`；此前网络 ECONNRESET 已在最终重试恢复 |
| 实际服务 `GET /api/openapi` | HTTP 200，151 个路径；从最终打包服务重新生成 `docs/openapi.json`，包含团队目录及 AI 确认接口 |
| `openspec.cmd validate --all --strict` | 39 项通过，退出 0；`openspec-final.log` |
| `git diff --check` | 退出 2；混合工作区仍存在行尾空白/混合换行提示，见 `diff-check.log`，未对其他模型改动进行批量格式化 |

安全验证包含联系方式组织关系隔离、非法筛选/受保护字段拒绝、授权下载；可靠性验证包含版本冲突无部分写入、并发幂等及迁移保留历史数据。它们不替代性能、设备和真实供应商验收。

## 仍未通过或未验证

全量验收未通过，不得将本批或整个 OpenSpec 标记为功能全部完成。后端旧断言包含多级审核、缺少 expectedVersion、将审核 ID 当任务 ID；TaskDispatch 的旧日志用例仍使用未来日期提交、已停用阅读登记和日志修订审核。需按新规则更新有效场景，并继续区分夹具过期与产品缺陷。

Flutter 剩余失败覆盖旧 RETURNED/团队目录/日志内容接口“不可用”断言、评论夹具、成果附件旧占位文案、日志重试 UI，以及既有 Demo、月历、工作台和小屏截图用例。不能把全部失败都归为夹具问题，须逐条复核实际 UI 行为。APK 未安装到设备，TalkBack、性能、手工链路均未验证。

OpenAPI 导出期间 SpringDoc 记录 MemberLogCalendar.days.additionalProperties 反序列化警告；实际 HTTP 响应与快照保留正确的 map/string enum 结构，尚未完成 Swagger UI 展示验证。APK 构建有 CupertinoIcons 字体提示，未阻断构建。

后续顺序：修正旧契约用例并修复证实的缺陷 → 重跑全量后端/Flutter → 设备和必要手工链路验收 → 记录部署目标 PostgreSQL 版本验证 → 在混合改动归属清晰后按仓库流程提交、PR、审阅。不要修改已发布 Flyway 历史迁移。
