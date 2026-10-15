# lyb 合并 main 后的运行与迁移

当前合并 main 64e2126（此前批次为 0aada7e），保留远端任务、日报和客户端功能，同时保留 B 的认证、组织与审核安全校验。审核服务同时注入 ReviewRepository 和 TaskRevisionService，任务修订使用远端实现。

## 数据库兼容

- 全新数据库：Flyway 按 V1–V12 初始化。
- 已运行 main V1–V11 的数据库：保留原迁移文件，新增 V12 登录防护表。远端 V10 已包括任务与记忆审核类型约束，本地重复约束迁移不再保留。先备份，再启动应用升级。
- 已运行旧 lyb 认证 V5 或临时认证 V10 的开发数据库：该 V5 与 main 的任务 V5 含义不同，不能直接启动新应用，也不能通过 repair 掩盖差异。本次没有修改旧库或清空卷。

旧 lyb 用户可以保留旧库，使用新的 Compose 项目和端口启动独立开发环境。复制 deploy/backend/.env.example 为本地环境文件，填写独立密码和管理员信息；补充 NEO4J_PASSWORD，并配置未占用的 POSTGRES_PORT、REDIS_PORT、NEO4J_BOLT_PORT、SERVER_PORT，然后运行：

```powershell
docker compose -p workpanel-merged -f deploy/backend/compose.yaml --env-file deploy/backend/.env.merged up -d --build
```

项目名 workpanel-merged 使用独立命名卷。不要运行 down -v 或删除旧卷。旧数据若需迁入新环境，必须先备份并制定数据转换方案；本次不自动重写 Flyway 历史记录。

## 拉取后的验收

需要 JDK 21 与 Maven，或 Docker Desktop Linux engine。完整后端验收：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven
```

先执行 docker build -t collaboration-data-runtime:local -f deploy/runtime/Dockerfile deploy 构建统一数据库镜像。脚本使用隔离 PostgreSQL/Redis/Neo4j，执行 clean verify，避免迁移重命名和类移动后残留旧构建文件。测试容器结束后自动清理，不使用开发数据库。Flutter 页面仍需依据 mobile/README.md 配置真实后端地址；后端测试通过不等于全部客户端联调通过。

## 2026-10-15 旧主线 0aada7e 实测结果（不代表当前版本）

- 全套 115 项：114 通过，1 失败，0 错误/跳过。B 的 33 项、远端任务转派/改期与日志相关测试通过。
- 唯一失败：BackendIntegrationTest.registrationAndIndependentOrganizationReview 第161行期望团队2人，但远端夹具已把 reviewer 加入团队，实际3人。遵照用户要求，公共测试与 origin/main 一致，留给 E 修正断言，不削弱权限规则。全套命令仍会返回失败。
- 空库 V1–V11 初始化和 HTTP 服务启动通过；从 main V9 升级至最新版本并保留既有用户的测试通过。
- OpenSpec 严格校验26项全部通过。任务生命周期规格的过长描述移入场景，规则含义不变。
- B 端到端测试使用独立管理员，临时隔离默认公司审核人并在结束后恢复，避免公共测试的密码修改、部门审核人和职责影响用例。
- 原始日志位于忽略目录 output/merge-main-backend-test.log、output/merge-main-openspec.log。旧文档中的33项结果是历史批次证据，本节为本次合并结果。
- Git 差异检查发现远端已有许可证与文档空白警告，未改写第三方许可证；本次冲突标记已清除。

本次没有验证 Flutter 实机界面，也没有转换已执行旧认证 V5 的数据库；不能据此声称所有电脑和已有库无条件直接可用。

## 最新 main 64e2126 合并验收

- 保留远端 MEMORY 审核与任务/日志能力，融合 B 的独立审核、实时身份复查及列表 repository。OpenSpec 导航描述和带 Neo4j 的测试脚本采用远端实现。
- 保留 main V1–V11；认证迁移为 V12。删除本地重复的任务审核约束迁移，远端 V10 已包含 MEMORY、TASK_REASSIGN、TASK_RESCHEDULE，避免覆盖或遗漏。
- B 专项33项全部通过，0失败/错误/跳过，clean verify与JAR打包成功；包含全新V1–V12数据库与主线V11→V12保留用户升级测试。证据 output/main-64e2126-member-b-test.log。
- OpenSpec严格校验28项通过。全仓Neo4j测试尚未执行：构建统一数据库镜像时auth.docker.io连接超时，不能沿用上一版114/115结果作为最新验收。
- 公共测试的团队人数问题已由main修正；B未改写公共测试。须待完整环境就绪后执行全套回归，再完成task 5.4。
- Flutter静态契约核对：组织树使用readCompleteList读取完整人员分页；ACCOUNT_DISABLED仍显示通用无权限提示，待E调整。尚无E确认记录，也无真实Android界面联调证据。
- 日志LogApi仍无审核最终应用接口；review中日志、仪表盘与记忆最终应用仍含跨模块SQL。task 4.1/4.5保持未完成，不以已有TaskRevisionService接入替代完整分层。
- 原本地未提交OpenAPI已保存在output/openapi-before-main-64e2126.json与命名stash，工作文件采用远端快照；B扩展与运行时快照仍需核对。