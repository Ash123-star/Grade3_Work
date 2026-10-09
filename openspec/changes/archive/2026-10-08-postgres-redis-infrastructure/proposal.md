## Why

现有项目只有移动端演示，缺少 PostgreSQL 数据结构、可执行迁移和 Redis 部署。需要为后续双端服务建立可重复部署的数据基础，并实际启动验证。

## What Changes

- 按方案建立组织、权限、任务、日志、复核、消息和 AI 业务表及必要约束。
- PostgreSQL 分段 SQL 集中到独立目录，按固定顺序合成一个带事务、版本记录的迁移 SQL，生成独立 ZIP 包。
- Redis 配置、启动及验证脚本独立成包，使用认证和 AOF 持久化。
- Docker Compose 启动两个独立服务、具名数据卷和健康检查；提供统一启动和验证入口。
- 执行迁移、重复执行和失败约束验证，记录实际结果。业务 API 和管理员密码初始化仍由后续服务端变更实现。

## Capabilities

### New Capabilities

- `data-infrastructure`: PostgreSQL 数据模型、版本化单文件迁移、Redis 独立包及容器运行验证。

### Modified Capabilities

无。

## Impact

新增 deploy/、scripts/、docs/ 和构建产物忽略规则；依赖 Docker Compose、PostgreSQL 16、Redis 7 和 PowerShell。数据端口仅绑定本机；不改现有移动端演示或已有容器。
