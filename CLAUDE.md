# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

仓库级开发约束（OpenSpec 流程、分层、Git/PR 格式、验收口径、项目特定规则）以 AGENTS.md 为准，此处不重复：

@AGENTS.md

产品基线是根目录 `方案.md`；OpenSpec 全局上下文和各模块负责人分工见 `openspec/config.yaml`（例如成员 B 不直接修改 `Security.java`、`Actor.java`、`Db.java`、`Business.java`、`OpenApi.java`）。

## 常用命令（Windows / PowerShell）

```powershell
# 规范校验（需要 OpenSpec 的规划阶段和归档前必跑；简单修改按 AGENTS.md 直接处理）
openspec.cmd validate --all --strict

# 后端编译
mvn.cmd -f server/pom.xml -DskipTests compile

# 后端完整验收：启动随机端口的隔离数据容器（PostgreSQL + Redis + Neo4j），执行 mvn clean verify 后清理
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1            # 本机 Maven
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven # 资源不足时在 maven 容器内运行
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -KeepContainers

# 后端单个测试类（纯单元测试无需数据库；@SpringBootTest 集成测试需要 DB_URL/REDIS_*/NEO4J_* 等环境变量）
mvn.cmd -f server/pom.xml test -Dtest=TaskStateMachineTest

# 后端本地启动（需先复制并填写 deploy/backend/.env）
powershell -ExecutionPolicy Bypass -File scripts/start-backend.ps1
```

- `test-backend.ps1` 依赖本地镜像 `collaboration-data-runtime:local`，没有时先运行 `scripts/start-data.ps1`（会 `docker compose build data`）。Docker 不可用时不能报告测试通过。
- 后端地址 `http://127.0.0.1:8080/api`，Swagger `/api/docs`，OpenAPI `/api/openapi`。
- `BackendIntegrationTest` 运行时会把运行时 OpenAPI 写回 `docs/openapi.json`，因此跑后端测试会改动该快照，提交前确认这个差异是否属于本次工作。

### Flutter（`mobile/`）

Flutter 位于 `D:\flutter`，未加入 PATH 时使用 `D:\flutter\bin\flutter.bat`。`flutter pub get` 访问 GitHub 常超时，验收时用 `--no-pub` 复用 `pubspec.lock` 已有依赖。

```powershell
cd mobile
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat test --no-pub --dart-define=USE_MOCK=true
D:\flutter\bin\flutter.bat test --no-pub --dart-define=USE_MOCK=true test/calendar_agenda_test.dart   # 单个文件
D:\flutter\bin\flutter.bat run --dart-define=USE_MOCK=true                                            # 离线 Mock 演示
D:\flutter\bin\flutter.bat run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

- `USE_MOCK` 和 `API_BASE_URL` 是编译期常量（`lib/core/config.dart`），Hot Reload 不会生效，必须重新运行或重新构建。默认 `USE_MOCK=false`，Android 默认地址 `10.0.2.2:8080/api`。
- Windows 中文用户名导致 Pub 缓存路径报错、或 sqlite3 原生库下载超时时，在仓库根目录运行 `scripts/repair-flutter-pub-cache.ps1` 和 `scripts/prepare-flutter-sqlite.ps1`（详见 `mobile/README.md`；`flutter clean` 后需重跑后者）。
- 测试截图写入 `output/flutter-evidence/`，过程日志写入 `mobile/.diagnostics/`，两者都被 Git 忽略。

### Web（`web/`，Vue 3 + Vite + vue-flow）

```powershell
cd web
npm run dev        # 127.0.0.1:5173，/api 代理到 VITE_API_TARGET 或 http://127.0.0.1:8080
npm run build      # vue-tsc 类型检查 + vite build
npm run test:e2e   # Playwright，tests/ 目录，desktop 与 mobile 两个视口，默认使用本机 Chrome（CHROME_PATH 可覆盖）
```

## 架构要点

### 后端（`server/`，Spring Boot 3.4 / Java 21，JDBC + Flyway + Redis + Neo4j）

- 业务模块位于 `cn.workpanel.module.<feature>`（auth、organization、task、log、review、message、analytics、ai、aiwork、memory、attachment、dashboard、comment、procedure），按 `api / application / controller / domain / infrastructure / dto` 分包。部分模块（如 `task`）在模块根包中还有直接的服务类（`TaskDispatchService`、`TaskLifecycleService`、`TaskStateMachine` 等）。
- 根包 `cn.workpanel` 只保留跨模块基础设施：`Db`（统一 JDBC 适配器，无 ORM）、`Business`（集中的组织数据范围规则）、`Security` / `Actor`（认证与身份上下文）、`Limiter`、`ApiError`、`OpenApi`，以及 AI 记忆/RAG 相关的 `Memory*`、`Rag`、`Development`。新增数据范围校验应复用 `Business`，不要在模块里另写一套。
- `cn.workpanel.contract`（ActorContext、DomainEvent、分页、版本契约）和 `cn.workpanel.shared` 是公共契约，不暴露数据库行或 HTTP 请求对象。
- 关键写入携带版本号，冲突返回 `409 VERSION_CONFLICT`；业务写入、通知 outbox 和审计在同一事务提交，通知投递失败不回滚业务。
- 数据库只认 `server/src/main/resources/db/migration/V*.sql`，新增迁移使用下一个版本号。`deploy/postgresql/` 是独立的数据基础设施包（由 `scripts/build-data-packages.ps1` 打包），不能用于后端业务库。
- 配置全部来自环境变量（`server/src/main/resources/application.yml`）：`DB_*`、`REDIS_*`、`NEO4J_*`、`DEEPSEEK_API_KEY`、`ADMIN_*`、`AI_*` 开关等。
- 接口变更要同步三处：运行时 SpringDoc、`docs/openapi.json`、`docs/backend-interface.md`。`docs/mobile-openapi-contract.yaml` 是标记为 PROPOSED 的移动端草案，不代表后端已实现。

### Flutter 客户端（`mobile/`，Riverpod + GoRouter）

- `lib/data/repositories/repository.dart` 定义数据接口，HTTP 实现与 `mock_repository.dart` 可替换，由 `USE_MOCK` 决定。真实模式 HTTP 失败时不得回退成 Mock 成功。
- `lib/routing` 管理五栏导航；`lib/features` 按导图、视图、日志、AI 地图、我的等页面组织；`packages/cute_ui` 是 path 依赖的本地组件包（OpenMoji 署名在其 `ATTRIBUTION.md`）。
- 客户端 guard 只用于交互限制，权限和数据范围以服务端为准。

### 前后端对接现状

`mobile/handoff.md` 记录了当前移动端请求与后端实现之间的接口缺口（按 P0/P1 排列）和历史测试结果，开始移动端或接口相关工作前先读它。`docs/backend-interface-gaps.md` 是更早的登记，其中部分条目已过期，需对照当前代码核实。
