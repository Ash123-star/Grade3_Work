# 成员 B 第一阶段交付（2026-10-16）

关联 Issue #3、#4、#5；OpenSpec member-b-backend-readiness；分支 lyb。
本阶段提交供审阅，尚不满足合并 main 后直接展示的最终验收门槛。

## 已实现与证据

- 合并 main 64e2126，保留任务、日报、记忆功能；保留 main V1–V11，认证新增 V12。
- 认证、组织及审核安全闭环；审核应用层通过 ReviewedRevisionApplication 调用任务、日志、组织、仪表盘与记忆模块；审核 SQL 集中至 ReviewRepository。
- 业务写入失败时审核决定、业务值、审计和 outbox 一并回滚；重复审批不能重复写入。
- B 专项 36 项全部通过，clean verify / JAR 打包成功（output/stage-member-b-isolation.log）。覆盖旧 V5/V10 独立 schema 升级、保留账号/登录状态、拒绝原库直接转换。
- OpenSpec 严格校验通过；git diff --check 通过。
- 独立展示启动脚本已实际启动后端，健康检查通过；凭据随机生成，仅保存在忽略目录 output/stage-demo。
- Flutter 99 个锁定依赖补齐；pub get --offline --enforce-lockfile 成功。修复停用账号提示、17 个测试的个人 SDK 字体路径。

## 尚未完成（合并前必须补齐）

- 最新完整后端回归：此前原有 123 项通过，但新测试夹具失败；随后修正并通过 B 的 36 项。最终全套运行中断、无成功退出码；2026-10-16 再次执行因 Docker 引擎未启动受阻。
- Flutter 全套测试首次运行失败（个人字体路径、测试模式）；路径已修复但未完成修复后回归。真实 HTTP 客户端测试已编写，未取得成功结果；未完成浏览器/Android 手工界面验收。
- 旧开发库已备份并恢复独立副本，CLI 因 PowerShell Java 参数解析失败；参数已修正，尚未重跑端到端升级。原库没有修改。升级工具不是可直接用于正式数据的已验收工具。
- 尚无 C/E 的人工契约确认；Sprint 待关联；本 PR 不自动关闭 Issue，不归档 OpenSpec。

## 可复现验收

1. 启动 Docker Desktop（Linux engine），安装 JDK 21 / Maven 或使用 Docker Maven。
2. 仓库根目录：docker build -t collaboration-data-runtime:local -f deploy/runtime/Dockerfile deploy。
3. powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven。
4. powershell -ExecutionPolicy Bypass -File scripts/start-stage-demo.ps1。检查 /api/health 和 /api/docs；凭据见 output/stage-demo/access.txt，首次改密。
5. mobile 目录运行 flutter pub get，再运行 flutter test 和 flutter analyze。Flutter SDK 3.38.7；不要沿用其他成员的绝对 SDK 路径。
6. 真实联调需显式设置 RUN_STAGE_INTEGRATION=1、STAGE_DEMO_DIRECTORY=<仓库>/output/stage-demo，再运行 flutter test test/member_b_real_backend_test.dart；会在独立展示库生成演示账号和组织。
7. Web 预览：flutter run -d web-server --web-port 5175 --dart-define=USE_MOCK=false。Android 模拟器地址为 http://10.0.2.2:8080/api。

## 数据和回滚

新库及 main V11 正常使用 Flyway 升至 V12。旧 lyb V5/V10 库不能直接运行新应用；upgrade-legacy-lyb-clone.ps1 仅备份恢复到随机命名副本，核对已知脚本校验和后转换历史并补跑迁移。未知历史拒绝处理，原库保留。该脚本端到端验收待完成；勿对正式库使用。不得执行 down -v、删除原卷或修改已发布 SQL。应用回滚不自动回退数据结构。

发布前发现远端 main 已推进至 8294d23（PR #17）；本阶段代码基于 64e2126，尚未吸收此次新增提交。合并前需解决与最新 main 的兼容性并重跑受影响验收。
