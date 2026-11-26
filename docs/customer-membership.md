# 二期客户、会员与权益（C）

本模块是二期 C 的后端主数据：客户档案、统一客户 ID、商城会员、年卡/权益、核销和服务进度。入口 `/api/customers`，首版仅 ACTIVE ADMIN；角色权限待 B 与甲方确认后集中调整。A 的 CRM 界面、D 的线下业务和 E 的商城同步通过客户 ID/外部 ID 关联，各自不复制客户表。

## 数据

- `customers`：个人/企业客户，`cus_` 统一 ID；`external_id` 为公司内唯一商城外部 ID，可空。
- `customer_memberships`：每客户一条商城会员绑定（商城会员 ID、等级、加入/到期、状态）。
- `customer_benefits`：每客户多条年卡/权益，带有效期和可选次数上限。
- `customer_benefit_redemptions`：核销记录，`(company, benefit, event_key)` 唯一，与权益使用同一公司和客户；保留首次核销的 `used/remaining`。
- `customer_progress`：会员服务阶段和说明。
- Flyway：`V37__customer_membership.sql`、`V38__customer_redemption_receipts.sql`。如某环境已单独应用 V37 且写入核销记录，V38 会停止并保留数据；需先确认历史回执处理方案，不要清空核销表。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/customers` | 分页搜索客户；search/kind/cursor/limit |
| POST | `/api/customers` | 新建个人/企业客户 |
| GET | `/api/customers/external/{externalId}` | 商城外部 ID 反查统一客户 |
| GET | `/api/customers/{id}` | 详情：customer/membership/benefits/progress |
| PUT | `/api/customers/{id}` | 更新档案，带 version |
| PUT | `/api/customers/{id}/membership` | 绑定/更新商城会员；首次 version=0 |
| GET | `/api/customers/{id}/benefits` | 权益列表 |
| GET | `/api/customers/{id}/benefits/{benefitId}/redemptions` | 权益核销历史 |
| POST | `/api/customers/{id}/benefits` | 发放权益 |
| POST | `/api/customers/{id}/benefits/{benefitId}/redemptions` | 核销，必须 `Idempotency-Key` |
| GET | `/api/customers/{id}/progress` | 服务进度列表 |
| POST | `/api/customers/{id}/progress` | 追加服务进度 |

核销规则：校验公司、客户与权益的归属后，同权益同 key 只记一次并返回首次记录和次数，即使客户后来归档或权益停用、过期；不限次数时 `remaining` 为 `null`。新核销在客户归档、权益停用、上海当天不在有效期或次数用完时返回 409；客户/权益不匹配或跨公司返回 404。外部 ID 冲突 409，不自动合并客户。

E 按当前客户的 `membership.mallMemberId` 匹配公司内商城快照。A 可使用统一客户 ID 调用 [商城会员与订单查询](backend-interface.md#二期商城-apicommerce)，由服务端执行绑定和权限校验。

## 权限与边界

- 首版 `CustomerService.admin()` 刷新 ACTIVE ADMIN 并拒绝首次改密；普通员工、创始人等角色待 B 确认后放开。
- 不实现商城拉取、订单金额、经营概览（E），不实现线下业务表（D），不实现 CRM 页面（A），不含合同/员工档案（B）。

## 验证

2026-11-26 在 Windows、Java 21 和隔离 PostgreSQL 16.15 上执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -Tests CustomerDraftTest,CustomerIntegrationTest,CustomerMigrationUpgradeTest
```

12 项通过，0 失败，BUILD SUCCESS。覆盖客户与会员基础接口、隔离空库及有数据的 V36 库升级至 V38、同键并发仅扣一次、后续核销和状态变化不改写首次回执、跨客户与跨公司核销拒绝，以及 V37 已有核销时安全停止升级。

未覆盖：共享环境的 Flyway 状态、A/D/E 端到端联调、最终角色权限、真实商城接口。
