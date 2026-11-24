## Why
二期需要统一管理个人和企业客户、商城会员、演出年卡资格、权益使用记录及会员服务进度，并让线下业务与商城通过统一客户 ID 关联。当前系统只有员工/组织与任务数据，没有客户域；不建立统一客户主数据会导致各模块重复建档和越权读取。

## What Changes
- 新增客户档案（个人/企业）、统一客户 ID 和公司内唯一的商城外部 ID 查询。
- 新增商城会员绑定、年卡/权益发放（有效期、可选次数上限）和核销记录。
- 核销使用 `Idempotency-Key`，同一权益同一键只扣一次；过期、停用或次数用完拒绝。
- 新增会员服务进度记录，供 CRM 与服务人员回查。
- 首版仅允许 ACTIVE ADMIN 访问；角色细化由 B 与甲方确认后集中调整。

## Capabilities
### New Capabilities
- `customer-membership`：客户档案、统一 ID、商城会员、权益有效期/核销和服务进度。

### Modified Capabilities
无。本变更不修改任务、日志、审批、组织权限或商城侧实现。

## Impact
- 新增 server `module/customer`、Flyway `V37__customer_membership.sql`、客户/会员/权益/核销/进度接口与单元测试。
- 不新增 Flutter 页面；A 的 CRM 界面和 E 的商城同步使用本接口。D 的线下业务只保存客户 ID。
- 首版入口为 `/api/customers`，仅 ADMIN；权限不足 403，跨公司一律 404。
- 验证：`javac` 局部编译通过；完整 Maven/PostgreSQL 集成测试与真实商城联调尚未执行。
