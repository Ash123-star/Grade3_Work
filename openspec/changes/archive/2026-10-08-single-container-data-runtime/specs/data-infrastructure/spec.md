## MODIFIED Requirements

### Requirement: Separate reproducible packages
系统 SHALL 分别输出 PostgreSQL 和 Redis ZIP，保留 UTF-8 说明及单组件源文件和工具，额外输出单容器统一运行包，排除本地密码和数据库数据。

#### Scenario: Build packages
- **WHEN** 执行构建脚本
- **THEN** PostgreSQL 包包含分段源文件与单文件迁移，Redis 包包含配置和验证入口，统一运行包提供单容器双进程启动，SHA256 清单可核对产物

### Requirement: Healthy persistent Docker services
系统 SHALL 通过 Compose 的一个 data 容器同时运行 PostgreSQL 与 Redis，设置各自认证、联合健康检查、独立持久卷和本机端口绑定；转换部署时关闭并移除本次旧两个独立容器。

#### Scenario: Start and restart
- **WHEN** 执行启动入口并重启容器
- **THEN** 本项目只有一个运行中的数据容器，两个数据库健康，已有迁移版本和 Redis 数据保留

#### Scenario: Redis authentication and failure
- **WHEN** 未认证客户端访问 Redis 或任一部署命令失败
- **THEN** Redis 拒绝未认证操作，部署入口报告非零错误而不是成功

#### Scenario: Child process failure
- **WHEN** 任一数据库主进程退出
- **THEN** 入口脚本停止另一进程并非零退出，容器按策略重启后恢复两个数据库

#### Scenario: Existing volume conversion
- **WHEN** 将本次已有两容器改成单容器
- **THEN** 旧容器停止和移除，已有两个数据卷继续挂载，不创建新的空卷替代原数据
