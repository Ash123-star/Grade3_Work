# PostgreSQL 与 Redis 部署

## 运行

需要 Docker Desktop（Linux 容器、Compose v2）和 PowerShell 5.1+。在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-data.ps1
```

首次生成私有 `deploy/.env`（两个独立的 256 位随机密码），构建组件包、统一运行包和组合镜像，在一个容器中同时启动 PostgreSQL 与 Redis，再显式执行迁移并验证认证。已有双容器部署会先停止并移除本次旧容器，继续挂载原数据卷。后续重复命令沿用已有密码及数据卷。凭据从本机 `.env` 读取，不提交 Git，不输出或打入 ZIP。

| 服务 | 本机地址 | 容器内地址 | 用途 |
|---|---|---|---|
| PostgreSQL 16 | 127.0.0.1:55432 | data:5432 | collaboration 数据库，collaboration_owner 用户 |
| Redis 7 | 127.0.0.1:56379 | data:6379 | 缓存、会话、限流 |

Docker Compose 项目默认 `collaboration-data`，只有一个服务 `data`、一个容器 `collaboration-data-data-1`，组合镜像 `collaboration-data-runtime:local`。容器中运行 PostgreSQL 与 Redis 两个必要的数据库进程，入口负责停止信号和进程退出联动，Docker init 回收子进程。任一数据库退出，另一进程也会优雅停止，容器按 unless-stopped 策略重启。

具名卷 `collaboration-data_postgres-data`、`collaboration-data_redis-data` 保持分开持久化；不会使用其他项目已有容器或卷。改变端口或密码在部署前修改 `.env`；数据库已初始化后不能仅改 `.env` 实现密码轮换。

```powershell
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
docker compose --env-file deploy/.env -f deploy/compose.yaml logs --tail 50
docker compose --env-file deploy/.env -f deploy/compose.yaml down
```

停止不带 `-v`，保留数据。再次执行启动入口即可恢复。当前只部署数据基础；移动端仍是演示，不代表 Spring Boot API 已接通。

## 文件与数据契约

- `deploy/postgresql/sql/`：组织权限、工作数据、复核消息 AI、索引种子四段 SQL。
- `deploy/postgresql/migrations/V001__initial_schema.sql`：唯一 V001 执行入口；全部语句在同一事务内，包含迁移锁、版本表和内容校验。
- `deploy/dist/postgresql.zip`、`redis.zip`：组件源文件和工具分别打包；默认部署入口仍只启动一个容器。
- `deploy/dist/data-runtime.zip`、`SHA256SUMS.txt`：统一单容器运行包及三个 ZIP 的 SHA256 清单；解压后在根目录执行 scripts/start-data.ps1。包内不含本地凭据或数据卷。
- `deploy/runtime/`：从官方 PostgreSQL/Redis 镜像组合的 Dockerfile、双进程入口和联合健康检查。
- `scripts/verify-data.ps1`：真实数据库约束、迁移重跑、校验漂移、失败回滚、Redis 认证和重启持久化验证。

| 业务域 | 表 |
|---|---|
| 组织、权限 | companies、departments、teams、users、roles、permissions、role_permissions、user_roles、reporting_relations |
| 任务、四象限 | tasks、task_assignees、task_events、dashboard_items、private_notes |
| 日报 | daily_logs、log_tasks、log_versions、log_reads |
| 复核、审计 | review_requests、review_steps、audit_records |
| 可靠消息 | outbox_events、notifications |
| AI 建议与地图 | ai_jobs、ai_map_nodes、ai_map_edges |
| 基础设施 | schema_migrations |

业务关联使用 company_id + id 外键。用户待确认状态默认 pending，插入自动赋员工角色；部门和团队归属组合约束，手机号全局唯一。任务主负责人只有一列，task_assignees 保存可选协作者；事件时间线承载业务流转，没有派发完成情况字段。日报按用户与业务日期唯一，草稿和提交状态明确；log_versions 保存修订，审核请求保存 base_version 和候选数据，数据库拒绝自审。

所有时间戳 timestamptz，容器 UTC；business_date 按 Asia/Shanghai 业务日期由服务端确定。公司基础种子 ID 为 `00000000-0000-0000-0000-000000000001`。只有基础组织权限与引导审计，没有默认管理员密码、任务或日志。种子名称后续可由正式复核业务修改，重跑迁移不覆盖。

## 后续接入边界

数据库不自动发布候选版本，也不实现完整权限、审批路由、停用会话撤销或幂等 HTTP 行为。后续 Spring Boot 对每个详情、聚合、搜索、导出和 AI 输入逐次鉴权；私人备注、未提交草稿不提供给上级。审核生效时比较 base_version，事务内修改、审计和 outbox 同步提交。

DeepSeek 密钥仅保存在后续服务端环境，不进入数据库。ai_jobs 的 input、output 和 sources 只存已授权且必要的业务文本，输出仍是建议。AI 无数据库写权限，用户确认后由正式业务 API 执行。

未来新增迁移用新版本，已执行 V001 不得重新生成不同内容。正式上线需补充受限应用数据库角色、备份恢复演练、TLS 和管理员安全初始化；这次交付范围是本地可验证的数据基础设施。

## 验证入口

`powershell -ExecutionPolicy Bypass -File scripts/verify-data.ps1` 用于本次新初始化的本地环境：验证默认种子计数，临时事务检查业务约束，创建后删除隔离测试数据库，并重启唯一的数据容器检查两个数据库持久化。已扩展组织或投入业务使用的环境应采用针对现有数据的验收，不直接使用默认种子计数断言。只检查迁移与约束、不重启时加 `-SkipRestart`。

实际执行结果见 `docs/data-infrastructure-validation.md`。

单容器进程联动验证入口为 `powershell -ExecutionPolicy Bypass -File scripts/verify-data-lifecycle.ps1`。它在本地验收环境分别停止 Redis、PostgreSQL 主进程，验证容器自动重启、两个服务同时恢复健康和测试键持久化；执行期间短暂中断两个数据库。
