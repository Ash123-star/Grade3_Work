# Tasks

## 1. 契约与数据
- [x] 1.1 新增 `V37__customer_membership.sql`：客户、商城会员、权益、核销、服务进度表及公司/外部 ID/幂等唯一约束；已在隔离 PostgreSQL 16 空库执行到 v37。
- [x] 1.2 实现 `/api/customers` 客户 CRUD、搜索、外部商城 ID 反查和详情聚合；验证为 `CustomerDraftTest` 与 `CustomerIntegrationTest`。
- [x] 1.3 实现会员绑定、权益发放、权益列表、核销历史和服务进度接口；验证为同一客户可关联多条权益与进度。

## 2. 核销与权限
- [x] 2.1 实现权益核销：唯一 key、权益归属、状态、有效期和次数上限校验；重复 key 返回原结果，过期/超次 409；真库 HTTP 验证通过。
- [x] 2.2 所有客户接口首版仅 ACTIVE ADMIN；跨公司读取和核销 404；验证为员工 403、跨公司 404。

## 3. 验收
- [ ] 3.1 在 PostgreSQL 执行 V37：空库 v37 已通过；V36→V37 升级库和唯一约束的独立升级测试待补。
- [x] 3.2 `scripts/test-backend.ps1 -DockerMaven -Tests CustomerDraftTest,CustomerIntegrationTest`：9 项通过、0 失败；覆盖创建/外部 ID 冲突、会员、权益、重复/过期/停用/归档核销、越权读取和进度。
- [ ] 3.3 与 A/D/E 联调：客户详情、线下业务保存客户 ID、商城外部 ID 反查；确认最终角色权限。

## 验证记录
- 2026-11-24：`scripts/test-backend.ps1 -DockerMaven -Tests CustomerDraftTest,CustomerIntegrationTest`，隔离 PostgreSQL 16 + Flyway 空库迁移至 v37，9 项通过、0 失败、BUILD SUCCESS。
- 未覆盖：V36 已有库升级、A/D/E 端到端联调、最终角色权限、真实商城接口。
