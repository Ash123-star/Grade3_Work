## MODIFIED Requirements

### Requirement: Healthy persistent Docker services
系统 SHALL 通过 Compose 的一个 data 容器同时运行 PostgreSQL、Redis 与 Neo4j Community，设置各自认证、三项联合健康检查、独立持久卷和本机端口绑定；升级 SHALL 复用 PostgreSQL/Redis 已有数据卷并安全停止本项目旧独立数据服务。

#### Scenario: Start and restart
- **WHEN** 执行启动入口并重启容器
- **THEN** 本项目只有一个运行中的数据容器，三个数据库健康，已有迁移版本、Redis 键和 Neo4j 节点保留

#### Scenario: Redis authentication and failure
- **WHEN** 未认证客户端访问 Redis 或任一部署命令失败
- **THEN** Redis 拒绝未认证操作，部署入口报告非零错误而不是成功

#### Scenario: Child process failure
- **WHEN** 任一数据库主进程退出
- **THEN** 入口脚本停止其余两个进程并非零退出，容器按策略重启后恢复三个数据库

#### Scenario: Existing volume conversion
- **WHEN** 将本项目已有数据部署扩展为三数据库单容器
- **THEN** 旧数据服务安全停止，已有 PostgreSQL/Redis 数据卷继续挂载，仅 Neo4j 使用新增独立卷

#### Scenario: Neo4j authentication
- **WHEN** 未认证访问图数据库或服务端使用有效凭据访问 Bolt
- **THEN** 未认证访问被拒绝，合法连接可执行受限应用查询，密码不进入构建产物或日志

### Requirement: Separate reproducible packages
系统 SHALL 分别输出 PostgreSQL 和 Redis ZIP，保留 UTF-8 说明及单组件源文件和工具，额外输出含 Neo4j 的单容器统一运行包，排除本地密码和数据库数据。

#### Scenario: Build packages
- **WHEN** 执行构建脚本
- **THEN** PostgreSQL 包包含源文件与单文件迁移，Redis 包包含配置和验证入口，统一运行包提供三数据库进程启动及联合健康检查，SHA256 清单可核对产物
