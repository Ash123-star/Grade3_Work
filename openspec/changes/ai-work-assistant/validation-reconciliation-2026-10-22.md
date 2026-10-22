# 主分支冲突协调验收

范围：任务 10.7 的工作区、Git 主线和迁移兼容协调。保留此前 4.2、9.6、9.7 的业务证据和原始失败，不重跑真实供应商语料，不把本批当成全部产品上线。

## 环境与命令

Windows / PowerShell，Java 21、Maven 3.9.9、Flutter 当前本机 SDK、真实 PostgreSQL/Redis/Neo4j 隔离测试容器、Chrome。使用 `output/ai-work-acceptance-temp`，原始结果全部在忽略目录 `output/ai-work-reconciliation/`。

- 后端：`powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -KeepContainers`，详情见 `backend.log` 与退出码。
- Flutter：`flutter analyze --no-pub`；`flutter test --no-pub --dart-define=USE_MOCK=true`。
- Web：`npm run build`、`npm run test:e2e -- --workers=2`。
- 规格：`openspec.cmd validate --all --strict`。
- 迁移：主分支 V15 正常升级、旧 AI V16/V17/V18 转换和未知历史拒绝的真实 PG 测试；本地数据库在线演练、停机最终恢复副本转换、所有业务表内容与序列比对、正常后端启动和登录读取。

## 已核对的差异

工作区 169 文件已保存 zip、SHA256 清单、二进制 diff 及安全 stash。当前工作分支实际快进到主分支 dc00e2b，未直接提交 main。主分支 V1–V15 均与 Git 原文一致。新增 AI SQL 只改文件编号为 V16–V18，内容/校验和不变；日志/评论/管理员能力保留。根应用锁文件恢复官方源，移除本机镜像 URL 漂移；独立 cute_ui 锁保留与项目 Dart 3.10.7 下限匹配的解析版本，不升级 SDK。测试生成的旧检索指标恢复主分支基线，原始本批指标保存在 output。

Flutter 全量首轮通知测试在固定 10ms 后读取尚未到达的事件而失败；改为有超时上限的实际流打开/通知事件信号。首次修正误把连接状态当成通知，定向发现后已过滤无 sequence 的状态信号，专项 6 项通过；最终全量 276 通过、1 跳过，退出 0。原两轮失败日志保留。生产通知语义未改变。

Flutter 分析退出 0。Web 类型/构建退出 0，浏览器 40 通过、4 个凭据依赖用例跳过，退出 0；真实本地登录/读取另记切换验证，不将跳过当成已验。

## 当前限制

GitHub 公开 API 确认 main=dc00e2b、当时无开放 PR。初次 Git HTTPS 访问 443 失败，之后网络恢复，两个实现提交已成功推送。GitHub CLI 未登录，但 Git 凭据认证的 GitHub API 可用，已创建 [Issue #24](https://github.com/Ash123-star/Grade3_Work/issues/24)，未将密钥写入文件或输出。正式 Sprint/故事分工与估算仍未安排，任务 1.1 保持待办。真机、20 并发性能、首次使用者和完整 Web 交付任务维持原状态，自动写入继续关闭。

## 后端和数据库结果

标准后端脚本首轮运行 394 项，其中 390 项原有回归全部通过；新增迁移测试有 1 失败、1 错误，原因是隔离 schema 由 Flyway 自动创建后多出一条 schema 元记录，未模拟实际已经存在的 public。修改测试夹具为先创建隔离 schema 后，定向运行 `mvn.cmd -B -f server/pom.xml -Dtest=AiWorkMigrationUpgradeTest verify`，4 项迁移测试全部通过、构建打包退出 0。累计 394 个不同测试有通过证据，属于全量回归加修正后的专项复验，不宣称首轮全过。原失败、390 项回归报告和专项报告均保留在 `backend-first-reports/`、`backend.log`、`backend-migration-verified.log/.exit`。

迁移测试覆盖 main V15 的用户/日志/同日志回复保留，旧 AI V16/V17/V18 的版本映射、原安装信息保留、重复运行幂等，以及错误校验和、缺版本、失败、重复、未知脚本/描述/类型/版本、缺关键表和非隔离目标的拒绝。普通 Flyway 校验通过。

在线本地数据库恢复演练退出 0：`rehearsal/result.json`，68 个业务表的所有原字段内容摘要和行数一致，所有 public 序列的值及 is_called 一致；既有任务、事项、附件、审计、outbox、回执无丢失。主分支的已发布脚本 15 份逐份相符，证据 `canonical-migrations.json`。备份与恢复副本保留，源库没有转换操作；协调镜像为 `workpanel-backend:ai-work-reconciled`。

严格 OpenSpec 校验 30 项通过、0 失败，退出 0。差异无冲突标记；UTF-8 与密钥扫描没有发现异常，最终扫描随提交再核对。

停机最终副本转换与切换退出 0：`promotion-result.json`、`final-20261022-172125/result.json`。68 个业务表与全部序列比对一致，删除标记已重放，旧库/旧 API 保留；新版后端连接 `workpanel_ai_upgrade_9ac0fd9b53f5`，健康 UP，普通 Flyway 校验启动成功。实际 sample-admin 登录后 `/auth/me`、`/ai/work-capabilities`、`/ai/work-items`、`/tasks`、`/logs` 全部 HTTP 200，执行开关 false，原库历史与协调前清单完全相同。证据 `live-api-result.json`、`live-api.exit=0`。

真实 Chrome 管理员登录、新办事台及任务审计导航通过，`live-web.log/.exit=0`；模拟器 emulator-5554 打开现有实际 API 版 App 成功。客户端生产代码与上一批已构建/安装 APK 一致，本次仅修改通知测试，不重复构建 APK，不把启动等同真机性能/完整交付验收。

本地提交：后端与迁移 `5847b47`，界面与续办 `92e6600`，均已推送 `origin/codex/ai-work-assistant`，`push.exit=0`。用于审阅的真实模拟器截图（合成测试数据）为 `docs/images/ai-workbench-reconciled.png`；工作区安全备份和 stash 保留。草稿 PR 创建结果另补，未合并 main。
