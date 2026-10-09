# Redis 数据包

默认使用统一单容器镜像中的 Redis 7，启用认证、AOF everysec、RDB 和独立数据卷。默认端口仅绑定 `127.0.0.1:56379`；256MB 内存上限，noeviction 保留会话和限流键，容量不足返回错误，由应用按用途处理。

独立解压使用：复制 `.env.example` 为 `.env`，设置独立随机 REDIS_PASSWORD（字母、数字、下划线或连字符），执行：

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
powershell -ExecutionPolicy Bypass -File verify.ps1
```

默认统一部署使用仓库 `scripts/start-data.ps1`，仅启动一个 data 容器同时运行 PostgreSQL 与 Redis。上面的独立 Redis 7 Alpine Compose 仅供单组件调试。统一容器手动验证使用 `verify.ps1 -ComposeFile ../compose.yaml -EnvFile ../.env -Service data`。使用哪个 Compose 文件启动，就继续使用同一文件维护服务；独立包和总 Compose 不混用。

`start.sh` 生成权限受限的临时认证配置；密码不会写入交付包，`auth-cli.sh` 使用容器内环境变量认证。验证脚本检查未认证访问拒绝、认证 PING 与 SET/GET，并删除临时测试键。Redis 保存缓存/限流/临时会话，正式业务数据保存在 PostgreSQL。

停止服务使用 `docker compose --env-file .env -f compose.yaml down`；不加 `-v`，数据卷保留。每秒 AOF 同步可能丢失崩溃前约一秒的数据，正式备份和上线网络/TLS 配置由后续部署完善。
