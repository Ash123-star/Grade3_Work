## Why

用户明确要求 PostgreSQL 和 Redis 只运行在一个 Docker 容器内。现有两个容器部署需要调整，且已有数据必须保留。

## What Changes

- **BREAKING** 统一 Compose 只保留 data 服务，在同一容器中管理 PostgreSQL 与 Redis 进程。
- 复用已有两个具名数据卷，沿用密码、端口及单文件迁移，停止并移除本次创建的旧独立容器。
- 更新启动、迁移和验证脚本，核对双进程健康、退出联动和重启持久化。
- PostgreSQL 和 Redis 仍分别打包；增加统一运行包以便恢复单容器部署。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `data-infrastructure`: Docker 默认运行形态变为同一容器双数据库，包内容和启动验收随之调整。

## Impact

修改 deploy/compose.yaml、数据库调用脚本及部署说明，新增 deploy/runtime/。停止范围限定本次旧 collaboration-data 容器，保留卷；不终止其他项目或正在使用的后端测试容器。
