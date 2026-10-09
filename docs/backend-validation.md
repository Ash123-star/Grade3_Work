# 后端验证记录

日期：2026-10-08 至 2026-10-09（Asia/Shanghai）。本次验证范围为 Spring Boot 后端；不代表 Flutter 已联网、Web 已完成或生产环境已上线。

## 实际通过

执行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven`，退出码 0。最终 Maven verify 为 BUILD SUCCESS，10 tests / 0 failures / 0 errors / 0 skipped，实际测试耗时 76.46 秒，包含打包的 Maven 总耗时 2 分 32 秒。

运行环境：Java 21、Spring Boot 3.4.2、真实 PostgreSQL 16.15、真实 Redis 7。测试数据库和 Redis 使用随机容器名、本机随机端口及随机凭据，结束后清理测试容器。供应商边界是本机模拟 DeepSeek HTTP/SSE 服务，模型没有真实外部调用和额度消耗。

| 场景组 | 已验证行为 |
| --- | --- |
| 初始化与登录 | 无默认管理员密码、首次改密、旧会话撤销、重复初始化不覆盖、注册角色注入拒绝、缺参错误和 OpenAPI 模式 |
| 组织与独立复核 | 待确认员工不能读业务、确认归属、驳回后改部门重提、复核职责不升级员工角色、任务复核策略旧版持续生效 |
| 任务权限及流转 | 范围外负责人拒绝、员工派发拒绝、同键重放和异内容冲突、并发幂等只创建一个任务、关键修订审核、接收/反馈/验收/归档、派发资格撤销 |
| 日报及审批链 | 草稿不穿透、每日唯一、提交历史、团队→部门→公司独立审核、自审及跳级拒绝、旧正文继续生效、过期审批冲突、驳回原因、已读与评语 |
| 导图隐私及附件 | 私人备注不进入公共响应、最多十项置顶、公开头像按面板范围下载、附件按任务授权、管理员关键修订保留派发者附件 |
| 时间与分析导出 | 跨年周一边界、上海业务日期转 UTC、提交率口径、CSV 同范围过滤及公式转义 |
| 可靠消息 | 回滚不留下 outbox、重复投递不重复通知、提醒去重、SSE 序号重放、全部已读 |
| AI 草稿及确认 | 无输出时重试、流式接收、选择来源解释风险、输入脱敏、无自动派发、建议来源/负责人结构校验、手动改稿版本、地图边、人工确认后正规幂等派发 |
| AI 失败与预算 | 供应商失败、格式无效、超时、取消、重试、日预算不足和限流；基础工作仍可用 |
| 撤权与公司隔离 | 调岗使旧日志/AI 来源不可读、过滤地图节点、停用撤销会话、汇报循环拒绝、跨公司 API 拒绝及数据库复合外键拒绝 |

测试报告位于 `server/target/surefire-reports/cn.workpanel.BackendIntegrationTest.txt`，完整运行日志 `server/target/integration-docker.log`；这些均为被忽略的构建产物。可执行 JAR：`server/target/collaboration-server-1.0.0.jar`。运行接口生成的静态契约已保存为 `docs/openapi.json`。

后端变更的 13 项任务全部完成，规范已同步并归档至 [2026-10-09-implement-collaboration-backend](../openspec/changes/archive/2026-10-09-implement-collaboration-backend/)。归档后执行 `openspec.cmd validate --all --strict`，退出码 0，全部 6 个活动规范/变更通过，0 项失败。

Docker 镜像 `workpanel-backend:local` 构建成功。`scripts/smoke-backend-image.ps1` 已验证镜像启动、三个 Flyway 迁移、OpenAPI 全部请求模式、首次登录强制改密及导图接口；随后以 PostgreSQL 自定义格式备份并恢复到另一个空库，恢复后管理员记录数为 1。运行日志 `server/target/image-smoke.log`。Compose（含 HTTPS profile）配置及四个 PowerShell 脚本语法校验通过。

## 实际限制

- 真实 DeepSeek 密钥、供应商模型可用性和生产额度未验收；模拟服务验证的是接口、流式、失败和权限边界。
- 生产域名及 HTTPS 证书签发尚未运行；已提供配置，数据库备份恢复已在隔离容器完成演练。
- 后端 AI worker 当前为单实例；多副本部署需增加任务租约、恢复及取消路由。
- Windows 本机提交内存不足曾导致 JVM 退出；最终改用限额 Docker Maven 执行并通过，普通 Java 运行也已限制测试内存。
- 现有独立数据包与本后端 Flyway 表结构不同，必须使用独立空库，不能原地覆盖已有数据基础包。
