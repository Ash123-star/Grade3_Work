## Context

现有数据基础已迁移并运行，用户纠正部署要求为一个容器运行两个数据库。SQL、端口、密码、数据卷继续沿用。

## Goals / Non-Goals

**Goals:** 在一个容器内运行 PostgreSQL 16 与 Redis 7，平滑复用卷并关闭旧两个独立容器；更新脚本与包后实际验证。

**Non-Goals:** 不调整业务表、公司范围、审核候选版本或双端 API 契约；不实现 DeepSeek 接入，密钥仍由未来服务端配置。

## Decisions

1. 以现有 postgres:16 为最终镜像，从官方 redis:7 Debian 镜像复制 redis-server 和 redis-cli，构建时验证二进制依赖。Redis 版本保持 7.4 系列可读取现有 AOF/RDB。
2. Compose 只定义 data 服务，同时暴露两个本机端口，挂载原 postgres-data 与 redis-data 卷。init:true 处理僵尸进程；入口脚本启动两个数据库并转发停止信号，一个进程退出时停止另一个并令容器失败，由 restart 策略重启。
3. PostgreSQL 使用官方初始化入口和 postgres 用户；Redis 使用专用 redis 用户，认证配置生成后限制权限。双健康检查必须同时成功。
4. 先构建新镜像，再关闭旧容器释放端口和卷，随后启动新容器、重跑已应用迁移并验证。显式移除旧容器，不删除数据卷、不停止其他项目或活跃测试容器。
5. 分开的 PostgreSQL 和 Redis ZIP 保留源文件及单组件工具，新增 data-runtime.zip 含统一 Compose、镜像入口、组件文件和启动工具；默认启动始终使用统一单容器。

## Risks / Trade-offs

- [任一数据库故障导致共同重启] → 双进程退出联动与联合健康检查，实际故障注入验收。
- [Redis 二进制或旧数据格式不兼容] → 使用官方 7.4 系列，构建时执行版本命令、转换前保存快照并验证重启读写。
- [已有数据被重复进程访问] → 启动新容器前确认旧容器已停止；卷始终保留。

## Migration Plan

构建镜像和包，确认 PostgreSQL 迁移版本与 Redis 原数据卷；优雅停止和移除两个旧容器；用原卷启动 data；确认迁移校验、Redis 加载原 AOF/RDB、认证和重启持久化；清理验证测试键。失败时保留卷用于恢复，不自动清空数据。
