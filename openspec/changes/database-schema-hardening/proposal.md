# Proposal

## Why

当前后端 Flyway 数据库能够支持主要业务流程，但部分关键完整性只依赖 Java 服务层，且日报关联任务仍嵌在 JSON 中。多人并行开发或出现脚本、后台任务直接写库时，可能产生跨租户引用、汇报环、自审步骤和无效任务关联，因此需要在客户端联调前固化数据库边界。

## What Changes

- 为后端 Flyway 数据库增加日报与任务的结构化关联表及跨公司外键。
- 用 PostgreSQL 触发器阻止汇报关系形成环，并用约束阻止审核申请人自审。
- 为关键 JSON、枚举、版本和状态字段补充数据库约束与查询索引。
- 更新后端日报和审核写入逻辑，使新增约束始终得到维护。
- 生成数据库字段字典和运行时数据库选型说明，明确后端 Flyway 与独立数据包的边界。

## Capabilities

### New Capabilities

- `database-integrity`: 为企业协作数据提供跨租户、关系、审核和业务引用完整性。

### Modified Capabilities

- `data-infrastructure`: 后端运行数据库增加结构化日报任务关联、汇报环保护和自审保护。

## Impact

- 新增 `server/src/main/resources/db/migration/V4__business_integrity.sql`。
- 修改日报和审核服务的数据库写入流程。
- 新增数据库字段字典及运行时数据库选型说明。
- 不改变现有 REST 路径、请求字段和客户端 API 契约。
