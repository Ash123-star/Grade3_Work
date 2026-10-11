# 后端验证记录

## 本机环境配置与当前版本回归（2026-10-11）

组员 B 本机安装 Temurin JDK 21.0.12.1，Maven 3.9.11 实际使用 Java 21；Docker Desktop 4.94.0 的 Linux 引擎启动成功，WSL 2.6.3 和固件虚拟化已启用。Flutter 3.38.7 / Dart 3.10.7 安装并按官方 SHA-256 校验；浏览器预览入口为 http://127.0.0.1:5175，默认演示模式。Android SDK 未配置，Google Maven 网络诊断超时，Android 构建及真实客户端联调未验收。

- `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven`：实际执行，10 tests / 1 failure / 0 errors / 0 skipped，未通过。测试使用独立 PostgreSQL/Redis 容器，结束后由脚本清理；DeepSeek 是模拟服务。
- 失败为 `BackendIntegrationTest.scopedTasksIdempotencyAndLifecycle` 第 172 行：团队长将任务转派给 `reviewer`，该人员不在其团队范围，接口返回 400 `INVALID_OWNER`，测试期待 200。组织场景仅给 alice/leader 配置该团队，未给 reviewer 配置。需 C/E 确认合法转派用例应选范围内人员，保留越权拒绝测试；不能为测试通过放宽服务端范围。
- 其余 9 个测试场景组通过，包含认证初始化、组织独立审核、日报审核链和版本冲突；这不表示所有未覆盖业务边界完成。
- `mvn.cmd -B -f server/pom.xml -DskipTests package`：BUILD SUCCESS，生成本地可执行 JAR。跳过测试打包仅用于本机启动，不视为验收通过。
- 全容器启动首次在 Docker Hub `auth.docker.io/token` 连接超时，后端 API 镜像未构建成功；实际采用 Compose 的 PostgreSQL 16 / Redis 7 容器，加本机 JDK 21 运行 API。数据库健康检查通过，Flyway V1—V4 成功执行。
- 本机 HTTP 冒烟：`/api/health` 为 UP；管理员登录、me 成功；首次改密标记 true，改密前访问组织返回 403，冒烟会话已登出。未自动修改用户初始密码。
- Swagger 原 `/api/docs` 重定向到 `/api/swagger-ui/index.html`，被现有过滤器以 401 拦截。仅在本机启动参数使用 `--springdoc.swagger-ui.path=/docs`；`http://127.0.0.1:8080/docs`、`/api/openapi` 均实测 200。公共鉴权/SpringDoc 路径需 E 后续统一，仓库代码未修复。

本机管理员为 lyb-local-admin，随机凭据保存在被 Git 忽略的 deploy/backend/.env；使用合成测试手机号，无真实个人资料和 DeepSeek 密钥。Issue 编号待关联。后端业务代码和测试预期未修改。

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

Docker 镜像 `workpanel-backend:local` 构建成功。`scripts/smoke-backend-image.ps1` 已验证镜像启动、四个 Flyway 迁移、OpenAPI 全部请求模式、首次登录强制改密及导图接口；随后以 PostgreSQL 自定义格式备份并恢复到另一个空库，恢复后管理员记录数为 1。运行日志 `server/target/image-smoke.log`。本次 V4 迁移新增的关系和约束需要在 Docker 环境重新执行完整验收。Compose（含 HTTPS profile）配置及四个 PowerShell 脚本语法校验通过。

## 实际限制

- 真实 DeepSeek 密钥、供应商模型可用性和生产额度未验收；模拟服务验证的是接口、流式、失败和权限边界。
- 生产域名及 HTTPS 证书签发尚未运行；已提供配置，数据库备份恢复已在隔离容器完成演练。
- 后端 AI worker 当前为单实例；多副本部署需增加任务租约、恢复及取消路由。
- Windows 本机提交内存不足曾导致 JVM 退出；最终改用限额 Docker Maven 执行并通过，普通 Java 运行也已限制测试内存。
- 现有独立数据包与本后端 Flyway 表结构不同，必须使用独立空库，不能原地覆盖已有数据基础包。
## 架构迁移复核（2026-10-09）

- `openspec.cmd validate --all --strict`：8 passed、0 failed。
- `git diff --check`：通过（仅提示现有文件换行符转换）。
- `mvn.cmd -f server/pom.xml -DskipTests compile`：通过，`BUILD SUCCESS`。
- `mvn.cmd -f server/pom.xml test`：测试编译阶段已发现并修复迁移后的测试字段引用；最终测试运行受 Maven 网络权限和外部 PostgreSQL/Redis 环境限制，未取得集成测试通过证据。
- `scripts/test-backend.ps1`：环境阻塞，当前执行器未安装 Docker（`docker is not recognized`）。
- 因上述环境限制，本轮不能报告编译或集成测试通过；代码完成度以源码迁移和 OpenSpec 校验为准，待具备 Maven 网络和 Docker 后重新执行。
