# PostgreSQL 数据包

使用 PostgreSQL 16。`sql/` 保存按编号排序的分段源文件；`migrations/V001__initial_schema.sql` 是合并后的单个纯 PostgreSQL SQL 文件。仓库中执行 `powershell -ExecutionPolicy Bypass -File scripts/build-data-packages.ps1` 可重新生成迁移和 ZIP。

独立解压使用：复制 `.env.example` 为 `.env`，为 POSTGRES_PASSWORD 设置随机密码，再执行：

```powershell
docker compose --env-file .env -f compose.yaml up -d --wait postgres
powershell -ExecutionPolicy Bypass -File migrate.ps1
```

默认统一部署使用仓库 `scripts/start-data.ps1`，仅启动一个 data 容器同时运行 PostgreSQL 与 Redis。上面的独立 Compose 仅供单组件调试。手动在统一容器中迁移时指定 `-ComposeFile ../compose.yaml -EnvFile ../.env -Service data`。使用哪个 Compose 文件启动，就继续使用同一文件维护服务；避免同项目名的独立和总 Compose 混用。

也可以使用本机 psql：设置 PGPASSWORD 后执行 `psql -X -h 127.0.0.1 -p 55432 -U collaboration_owner -d collaboration -v ON_ERROR_STOP=1 -f migrations/V001__initial_schema.sql`。密码不要写进命令行或仓库。

迁移使用事务、迁移锁和 SHA256 版本校验。同版本重跑跳过；同版本内容修改拒绝执行。后续升级新增 V002 SQL，禁止改写已执行的 V001；本迁移不删除已有数据，不提供自动破坏性回滚。恢复旧状态须使用事先备份。

基础种子只创建一个公司、产品部/市场部/技术部、五种角色及权限映射，不创建管理员。新公司必须先初始化角色，插入用户才会自动授予员工角色；管理员首登改密由后续服务端负责。

company_id 组合外键避免跨公司引用；不能替代服务端 RBAC、管理范围和私人数据鉴权。当前连接用户是本地部署管理员，未来应用需使用受限数据库角色。表和数据契约见仓库 `docs/data-infrastructure.md`。
