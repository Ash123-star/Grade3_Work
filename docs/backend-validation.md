# 后端验证与验收入口

本文件维护验证方式与当前结果入口，不逐轮堆叠环境安装和历史交付流水账。最新一次完整前后端联调的基线、命令、退出码及限制见 [2026-10-30 联调记录](frontend-backend-integration-validation-2026-10-30.md)。旧版本验证可从 Git 历史和相关 OpenSpec 查询。

## 五个 PR 集成与发布（2026-11-04）

本批次整合 #55/#57/#59/#61/#62，基线 main `afbdfce`，独立工作区 `chore/integrate-five-prs-20261104`；保留原工作区未提交改动，用户授权本次 Agent 审阅后合并。#59 日历已由 #65/#67 接入，保留 main 的 V27、完整任务行、落点及限流修复，整合原分支祖先关系和管理后台依赖。

- 升级选择追加 V28 创始人互审、V29 个人置顶、V30 多标签，不采用 Flyway out-of-order、不改已发布迁移。年度场景 V2 为第二创始人，V3 为多创始人协作；正式部署保持场景初始化关闭。
- 普通任务列表支持本人置顶排序；日历继续使用原日期顺序和快照，保留权限判断。多标签兼容旧零/单标签幂等摘要，异内容仍拒绝；管理后台审核接入当前 expectedVersion 校验。
- 节假日独立占行，故障不阻塞任务。#61 旧五行折叠设计由本日已发布的完整任务行要求替代。原日历设备性能、TalkBack 与人工矩阵缺口继续保留。
- 线上运行 systemd JAR；旧 Compose CI 部署仅在 workflow_dispatch 且 DEPLOYMENT_MODE=compose 时显式启用，避免合并时启动第二套 API。
- Windows PowerShell、Java 21、Maven 3.9.9、Flutter 3.38.7；真实隔离 Docker PostgreSQL/Redis/Neo4j。Docker 遗留通信目录改名保留，未重置数据卷。另建本机临时 PostgreSQL 仅用于预备诊断，未用于当前 Docker 验收。
- 最终验证（2026-11-05，Issue #69）：`scripts/test-backend.ps1` 退出 0，511 项、0 失败、0 错误、1 跳过，Maven clean verify / Spring Boot JAR 打包成功；`scripts/test-flutter.ps1 -Flutter D:/flutter/bin/flutter.bat` 退出 0，HTTP 50 项、Mock 373 项通过，5 项需要真实服务的 opt-in 测试跳过。`flutter analyze --no-pub` 无问题、退出 0；`npm ci` / `npm run build` 退出 0；`openspec.cmd validate --all --strict` 52 项通过、退出 0。
- 首轮失败已修复：审核测试补齐 expectedVersion、多标签扩展返回契约、去除重复关系夹具；AI 依赖失败测试在构造事项/步骤/回执期间暂停调度，避免夹具尚未构造完即被后台结算。月历保留完整任务行，测试点击日期空白位置；选择人员测试按新版组织搜索操作；日期筛选夹具跟随当前月份；外部测试容器在组件卸载时释放，避免遗留定时器。无屏幕尺寸的月历容器增加有效高度兜底，原卡住的组件测试及全量回归通过。
- JAR：`server/target/collaboration-server-1.0.0.jar`，SHA-256 `d3b002875e0f893a4d13d8cb83ac467d6aabb1cbdf098a17f913ac7631713183`。过程日志与界面截图保存在忽略的 `output/`；外部 DeepSeek/OCR、实体设备、TalkBack 和性能人工矩阵仍未补验，不能用本轮自动测试替代。
- 安全验收关注跨公司、待确认账号、自审、版本和个人置顶隔离；可靠性关注并发一次生效、同键重放、V27 向前升级及节假日故障降级。
- 已取得用户授权的服务器会话。部署须先核对实际数据库、保存并验证备份、逐字节比对已发布迁移，再替换 JAR、重启及检查健康和业务数据摘要；实际部署回执在执行后补录。

## 验证方式

在仓库根目录执行；需要 Java 21、Maven 与 Docker，环境和参数以脚本为准：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
# 本机资源受限时使用 Docker Maven
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven
```

脚本使用隔离资源，不应将实际业务数据库作为测试目标。镜像冒烟、真实 HTTP 场景、专项验证和灾备工具见 [脚本索引](../scripts/README.md)。需要维护 OpenSpec 时执行规范校验；简单修改按 [开发流程](development-workflow.md) 选择受影响检查，不为验证过程单独创建文档或 change。

## 当前待处理项

2026-10-30 的 442 项、49 失败、1 错误为历史结果；当前整合基线的完整后端回归已由上述 511 项、零失败零错误结果更新。目标设备、外部 DeepSeek/OCR、性能与无障碍仍有未验收范围，保留对应历史记录中的具体限制。

历史测试 JVM 等待退出后被强制结束的诊断仍见 [专项安全回归](member-b-security-regression.md)；构建成功不能据此宣称优雅退出已验证。旧数据库转换只允许按工具支持的已知历史先备份、恢复副本再校验，不改写已发布 Flyway 脚本或直接 repair 业务库。

后续结果更新现有主题文档或 Issue/PR，必须提供代码基线、环境、命令、明确退出码、结果及限制。过程日志与截图放被忽略的 `output/`。本次仓库清理没有运行功能测试，也没有部署或数据库修改。
