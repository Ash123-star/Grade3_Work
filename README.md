# 企业协作智能面板

企业内部协作系统，目标包含 Flutter Android 客户端、Web 管理端、Spring Boot 后端、PostgreSQL、Redis 和服务端 AI 助手。

产品基线见 [方案.md](方案.md)。当前仓库以 Spring Boot 后端和跨端界面基础工程为主，Android 联网接入、独立 Web 工作台和生产部署仍属于后续工作，不能将规划内容当作已交付功能。

## 当前状态

- 后端：Spring Boot 3.4、Java 21，使用 PostgreSQL Flyway 模型和 Redis。
- 接口：认证、组织、任务、日报、审核、通知、统计、附件、仪表盘和 AI 已有实现入口。
- 架构：按 `module/<feature>/{api,application,controller,domain,infrastructure,dto}` 分模块，公共契约位于 `contract` 和 `shared`。
- 权限：管理员/创始人全公司，部门负责人本部门，团队长本团队，员工本人；查询、导出、附件和 AI 输入均由服务端校验范围。
- 客户端：`mobile/` 为 Flutter 工程，部分页面仍使用演示数据。
- 验证：OpenSpec 严格校验通过；完整集成测试需要 Docker、PostgreSQL、Redis 和 Maven 依赖环境。

## 仓库结构

`server/` Spring Boot 后端、Flyway 迁移和集成测试
`mobile/` Flutter Android 客户端
`deploy/backend/` 后端 API、PostgreSQL、Redis 的 Compose 部署
`deploy/postgresql/` 独立数据基础设施包，不能与 server Flyway 混用
`deploy/redis/` Redis 配置
`doc/` 课程要求和产品资料
`docs/` 后端运行、架构、接口、数据库和验证文档
`openspec/` 需求变更、规格、设计和任务清单
`scripts/` 启动、测试、备份和数据初始化脚本

后端模块位于 `server/src/main/java/cn/workpanel/module/`，包括 `auth`、`organization`、`task`、`log`、`review`、`message`、`analytics`、`ai`、`attachment` 和 `dashboard`。根包仅保留应用启动、公共安全、数据库和错误处理能力，旧版根包 Controller 已删除。

## 文档入口

| 内容 | 文档 |
| --- | --- |
| 产品需求和导航基线 | [方案.md](方案.md) |
| 后端运行、部署和配置 | [docs/backend.md](docs/backend.md) |
| 后端分层、模块职责和依赖 | [docs/backend-architecture.md](docs/backend-architecture.md) |
| REST、SSE、附件和 AI 接口 | [docs/backend-interface.md](docs/backend-interface.md) |
| 数据库表和迁移说明 | [docs/database-schema.md](docs/database-schema.md) |
| 后端验证结果和环境限制 | [docs/backend-validation.md](docs/backend-validation.md) |
| 组员开发流程和 PR 约定 | [docs/development-workflow.md](docs/development-workflow.md) |
| OpenSpec 变更列表 | [openspec/changes](openspec/changes) |

## 后端快速启动

需要 Docker Desktop、Compose v2、Java 21 和 Maven 3.9：

```powershell
Copy-Item deploy/backend/.env.example deploy/backend/.env
# 编辑 deploy/backend/.env，填写数据库、Redis 和初始管理员配置
powershell -ExecutionPolicy Bypass -File scripts/start-backend.ps1
```

默认地址：`http://127.0.0.1:8080/api`；Swagger：`http://127.0.0.1:8080/api/docs`；OpenAPI：`http://127.0.0.1:8080/api/openapi`。

后端优先使用 `server/src/main/resources/db/migration/` 的 Flyway 模型。`deploy/postgresql/` 是独立数据基础设施包，不能直接用于后端业务库。

## 验证命令

```powershell
openspec.cmd validate --all --strict
mvn.cmd -f server/pom.xml -DskipTests compile
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
```

测试脚本会创建独立的随机容器和端口，并清理自己创建的资源。Docker 不可用时，不能把测试报告为通过，应在 [docs/backend-validation.md](docs/backend-validation.md) 记录阻塞原因。

## 开发约束

- 新能力先澄清需求、权限、数据、状态、异常、非目标和验收条件，再建立 OpenSpec 变更。
- Controller 只负责协议映射和输入校验；应用层负责事务和用例编排；领域层负责规则；基础设施层负责数据库、缓存、消息和外部服务。
- 数据库变更只能新增 Flyway 迁移，不能修改已发布迁移。
- 任务列表不得出现完成情况字段；下属日志入口固定在日志模块。
- AI 只能由服务端调用 DeepSeek，API Key 使用环境变量，结果必须人工确认后才能创建任务。
- 未通过测试或可重复检查不得标记功能完成。

详细规则见 [AGENTS.md](AGENTS.md) 和 [docs/development-workflow.md](docs/development-workflow.md)。

## OpenSpec 常用命令

```powershell
openspec.cmd list
openspec.cmd status --change initial-product
openspec.cmd validate --all --strict
```

Codex、Claude Code 和 CodeBuddy 共用 `openspec/config.yaml` 和变更目录。已归档变更位于 `openspec/changes/archive/`，未完成变更必须保留 proposal、design、specs 和 tasks。
