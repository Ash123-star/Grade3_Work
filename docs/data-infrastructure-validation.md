# 数据基础设施实际验证记录

验证日期：2026-10-08（Asia/Shanghai）。本记录仅涉及 PostgreSQL、Redis 和数据包，不代表服务端 API、移动端联网或初始产品任务完成。

当前运行方式已按用户要求改为一个容器同时运行 PostgreSQL 与 Redis。首次验证表格为原双容器部署的历史结果；最新单容器结果见末尾。

## 已执行

| 验证 | 结果 |
|---|---|
| scripts/start-data.ps1 | 成功生成两个包、创建数据卷、执行 V001 并启动两个容器 |
| PostgreSQL 初始结构 | public 下 27 张表（26 张业务表和 schema_migrations）；版本记录 1 条 |
| 基础种子 | 3 个部门、5 种角色；无默认管理员 |
| 默认时间 | UTC |
| 同迁移重跑 | 输出 already applied; skipped；种子计数不变 |
| 已执行版本校验漂移 | 非零退出，checksum mismatch |
| 错误迁移回滚 | 隔离测试数据库中注入除零错误；public 表数为 0；随后原迁移成功 |
| 业务约束 | 12 项非法写入被拒绝；用户默认 pending + employee；全部测试数据回滚 |
| Redis 认证 | 未认证 PING 返回 NOAUTH，认证 PING 返回 PONG |
| Redis 读写 | SET/GET 一致，临时键清理 |
| 重启持久化 | PostgreSQL 迁移及种子保持，Redis 测试键保留；两服务恢复 healthy |
| 独立包 | postgresql.zip 9 项、redis.zip 8 项；包内每项内容与源文件一致 |
| SHA256SUMS.txt | 两个 ZIP 校验和均匹配 |
| 配置隔离 | 私有 deploy/.env 和 deploy/dist 被 Git 忽略；包内不含私有 .env |
| Compose | 总配置及两个独立包配置验证通过 |
| OpenSpec | openspec.cmd validate --all --strict：6 项通过，0 失败（归档前） |
| 规范同步与归档 | 5 条需求同步到 openspec/specs/data-infrastructure/spec.md；变更归档到 2026-10-08-postgres-redis-infrastructure；归档后严格校验仍为 6 项通过、0 失败 |

V001 源 SQL 合并内容 SHA256：`86e22dc2db2e275620ffdd60427e032c0f2602df685cf442fa3be50b3f4ae1f7`。

业务拒绝用例：跨公司部门、部门团队不一致、重复手机号、循环汇报、重复日报、重复派发幂等键、跨公司协作者、自审、伪造审核申请人、无理由驳回、重复置顶位置、超过十项置顶。隔离测试数据库已删除。

## 首次双容器运行记录（已替换）

- collaboration-data-postgres-1：postgres:16，healthy，127.0.0.1:55432。
- collaboration-data-redis-1：redis:7-alpine，healthy，127.0.0.1:56379。
- 两个旧容器已优雅停止并移除，具名数据卷保留并改由新单容器使用。

尚待后续服务端变更交付：业务权限、管理员密码初始化、复核生效和 API 接入。其他项目原有 interview 容器及数据未做修改。

## 最新单容器验证

单一 Compose 服务 data、容器 collaboration-data-data-1、镜像 collaboration-data-runtime:local；PostgreSQL 16.15 与 Redis 7.4.11 同容器运行，端口仍为 127.0.0.1:55432 和 127.0.0.1:56379。

| 验证 | 实际结果 |
|---|---|
| 旧容器清理 | collaboration-data-postgres-1、collaboration-data-redis-1 停止后移除，无遗留旧进程 |
| 数据卷复用 | collaboration-data_postgres-data 挂载 /var/lib/postgresql/data；collaboration-data_redis-data 挂载 /data |
| 原数据库 | 官方入口输出 Skipping initialization；V001 输出 already applied; skipped |
| 原 Redis 数据卷 | 日志确认从原 appendonly.aof.1.base.rdb 和 incr.aof 加载成功 |
| 当前项目容器数量 | 只有 collaboration-data-data-1，状态 healthy |
| verify-data.ps1 | 迁移重跑、内容漂移、失败回滚、12 项业务约束、认证和容器重启持久化全部通过 |
| verify-data-lifecycle.ps1 | 分别停止 Redis、PostgreSQL，容器各自动重启一次并恢复联合 healthy，测试键仍保留且最终清理 |
| 重启配置修复 | Redis 临时配置迁至专用 /run/collaboration-redis 目录，重复启动不再触发共享 /tmp 文件权限问题 |

组件 ZIP 重新构建，新增 data-runtime.zip，包含单容器 Compose、组合镜像源文件、两组件配置与完整启动/验证工具。私有密码及数据卷均不进入包。

最新包核对：PostgreSQL 9 项、Redis 8 项、统一运行包 29 项；逐项字节内容与源文件一致，三个 SHA256 全部通过。重复执行启动入口仍只运行一个 data 容器，迁移跳过且 Redis 认证读写通过。归档前严格 OpenSpec 校验 7 项通过、0 失败。
