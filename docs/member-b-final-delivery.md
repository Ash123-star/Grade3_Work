# 成员 B 第二阶段验收与展示（2026-10-16）

关联 #3 / #4 / #5，OpenSpec member-b-backend-readiness，PR #18，分支 lyb。整合 main 8294d23，保留其任务、日报、记忆模块与 V12 审核类型约束；认证顺延 V13。第一阶段文档为历史记录，以本文为当前口径。

## 完成内容

- 认证、组织、分层独立审核及版本冲突控制；审核应用编排不再直接更新其他模块表，通过 ReviewedRevisionApplication 调用所属业务模块，事务覆盖业务值、审核状态、审计和 outbox。
- 原有权限保持不变；注册为待确认员工、禁止自审、缺独立审核人不生效、停用后旧会话失效。
- 保留已发布主线 V1–V12；旧 lyb V5/V10/V12 登录防护迁移只在备份恢复的独立副本上转换至 V13。未知校验和拒绝，原库不改。
- 修复 Spring Security 显式绑定 CORS 白名单；允许登记的本地前端来源，拒绝任意外域，不使用通配白名单。
- 展示脚本创建独立数据卷和随机凭据；修复含数字 NEO4J 配置名读取，允许显式选择已升级的副本数据库。
- Flutter 停用提示对齐后端；测试字体自动定位 SDK；同步主线 503 错误契约及重试退避等待；截图写入 output/flutter-evidence，不覆盖仓库历史证据。

## 已取得证据

- 最终后端全套 129 项通过，0 失败/错误/跳过，clean verify / JAR 打包成功；含 CORS 允许与拒绝测试（output/resume-backend-cors-final.log）。
- Flutter 全套 240 项通过，1 项真实后端测试默认跳过（需显式启用以免改动使用者数据库）。命令：flutter test --no-pub --dart-define=USE_MOCK=true。
- 单独真实后端测试 1 项通过：RUN_STAGE_INTEGRATION=1，STAGE_DEMO_DIRECTORY=<仓库>/output/stage-demo，flutter test --no-pub test/member_b_real_backend_test.dart。使用正式 HttpRepository 和真实 PostgreSQL，不使用 HTTP Mock Adapter。
- flutter analyze --no-pub：No issues found；flutter build web --no-pub --no-web-resources-cdn --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://127.0.0.1:8080/api 成功。
- 旧 V5 开发库、副本 V12 展示库均实际 pg_dump、pg_restore、升级和 Flyway 校验通过；源库及备份保留。V10 转换由真实数据库独立 schema 测试覆盖。
- 安全：组织隔离、自审、越权、凭据及旧会话测试；可靠性：业务写入失败回滚及并发不重复写；性能：MemberBPerformanceTest 随全套执行，详情保留本地测试日志。

原始日志在忽略目录 output/resume-*.log；数据、备份和随机凭据不提交 GitHub。系统：Windows、JDK21、Flutter3.38.7、PostgreSQL16、Redis7、Neo4j5.26 Docker 隔离环境。

## 新电脑运行

1. 安装并启动 Docker Desktop Linux engine；配置 JDK21 的 JAVA_HOME、Flutter SDK3.38.7（项目及 Pub 缓存推荐同盘英文路径）。首次联网下载依赖不可省略。
2. 根目录执行 docker build -t collaboration-data-runtime:local -f deploy/runtime/Dockerfile deploy。
3. 执行 powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven。
4. 执行 powershell -ExecutionPolicy Bypass -File scripts/start-stage-demo.ps1 -SkipBuild；打开 http://127.0.0.1:8080/api/docs。账号见 output/stage-demo/access.txt，首次改密；已有库更改环境变量不会重置密码。
5. mobile 目录执行 flutter pub get；浏览器展示建议构建上述携带本地资源的 Web 版本，再运行 python -m http.server 5175 --bind 127.0.0.1 --directory build/web，访问 http://127.0.0.1:5175。
6. 注册新员工后，用管理员处理注册自动生成的归属审核；员工确认后申请公司复核职责，管理员独立批准；管理员提交组织变更，由独立公司复核人审核。未审核前旧值不变。

旧 lyb 库另行执行 scripts/upgrade-legacy-lyb-clone.ps1 -SourceContainer <容器> -EnvFile <原本地配置>。读取成功输出的副本库名，使用 start-stage-demo.ps1 -SkipBuild -DatabaseName <副本库名>（该库必须位于展示 data 容器中）。不要对原库 repair，不删除原卷。停止展示 API 使用 output/stage-demo/api.pid 对应进程，保留卷。

## 边界和组长验收

- Android 真机/模拟器安装和触摸链路尚未实测；本次真实客户端是 Dart HttpRepository 与 Flutter 浏览器版本，不能等同于 Android 实机验收。Android 调用电脑后端使用 http://10.0.2.2:8080/api。
- DeepSeek 外部调用需要组员自己的服务端 Key；未配置时明确显示不可用，不以 Mock 代替 AI 实际生成。数据库检索及原有 AI 自动测试不等于外部模型实测。
- 组长需完成非作者审阅与组内设备演示验收；C/E 人工契约确认和 Sprint 归属仍待组内决定。不得声称已取得成员确认。
- ReviewApi 旧声明不作为已完成证据，实际跨模块最终应用边界是已接入的 ReviewedRevisionApplication。组织分页/错误码由真实客户端测试验证，接口快照随后端全套生成。
- 回滚不自动删除表或业务数据。后续 main 再新增迁移时需重新检查编号，不能覆盖已发布迁移。

## 浏览器验收补充
真实 Flutter Web 已完成登录及账号页检查，CORS 允许来源绑定已实测修复。账号截图见 member-b-real-profile.png（隔离合成演示账号）。现有 DraftDatabase Web 使用不支持的 stub，首页提示本机草稿读取失败；Web 仅用于认证、组织、审核及在线页面展示，不能用于离线草稿展示。Android 原生持久化由自动测试覆盖，实机尚未验收，此项继续跟踪，不以浏览器代替实机。
