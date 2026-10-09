# data-infrastructure Specification

## Purpose
定义企业协作的数据模型、版本化迁移、组件打包和可持久化的本地数据库部署，并规定公司关联隔离、业务完整性、密码保护、失败回滚和容器健康恢复的验收要求。
## Requirements
### Requirement: Company-scoped PostgreSQL schema
系统 SHALL 提供方案核心业务表，关联约束拒绝跨公司引用，用户默认待确认并关联员工角色；保存 UTC 时间与独立业务日期。

#### Scenario: Reject cross-company links
- **WHEN** 在一个公司下引用另一个公司的用户或组织
- **THEN** PostgreSQL 外键拒绝写入

#### Scenario: Shared data contract
- **WHEN** Android 和 Web 后续接入服务端
- **THEN** 两端共用该数据库定义和服务端权限契约，当前部署不代表 API 已实现

### Requirement: Business integrity
数据库 SHALL 保证手机号唯一、每人每天一份主日志、唯一任务主负责人、汇报关系无循环、审核步骤不能由申请人本人处理。

#### Scenario: Reject invalid business writes
- **WHEN** 写入重复日报、循环上级关系或自审步骤
- **THEN** 写入失败且原有效数据保持不变

### Requirement: Atomic single-file migration
系统 SHALL 将分段脚本合成为单个版本化 SQL，使用事务、串行迁移锁及内容校验，提供可重复执行的 psql 入口。

#### Scenario: Repeat same migration
- **WHEN** 对同一数据库重复执行相同版本和校验和的迁移
- **THEN** 跳过已完成迁移，不重复写入业务种子

#### Scenario: Changed or failed migration
- **WHEN** 已应用版本的内容发生变动或 SQL 执行失败
- **THEN** 返回非零退出码；失败事务全部回滚，不留下半成品业务表

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
