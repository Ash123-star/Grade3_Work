# 二期客户、会员与权益（C）

本模块是二期 C 的后端主数据：客户档案、统一客户 ID、商城会员、年卡/权益、核销和服务进度。入口 `/api/customers`，首版仅 ACTIVE ADMIN；角色权限待 B 与甲方确认后集中调整。A 的 CRM 界面、D 的线下业务和 E 的商城同步通过客户 ID/外部 ID 关联，各自不复制客户表。

## 数据

- `customers`：个人/企业客户，`cus_` 统一 ID；`external_id` 为公司内唯一商城外部 ID，可空。
- `customer_memberships`：每客户一条商城会员绑定（商城会员 ID、等级、加入/到期、状态）。
- `customer_benefits`：每客户多条年卡/权益，带有效期和可选次数上限。
- `customer_benefit_redemptions`：核销记录，`(company, benefit, event_key)` 唯一。
- `customer_progress`：会员服务阶段和说明。
- Flyway：`V37__customer_membership.sql`。

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

核销规则：同权益同 key 只记一次并返回原结果；权益停用、上海当天不在有效期、次数用完均 409；客户/权益不匹配或跨公司 404。外部 ID 冲突 409，不自动合并客户。

## 权限与边界

- 首版 `CustomerService.admin()` 刷新 ACTIVE ADMIN 并拒绝首次改密；普通员工、创始人等角色待 B 确认后放开。
- 不实现商城拉取、订单金额、经营概览（E），不实现线下业务表（D），不实现 CRM 页面（A），不含合同/员工档案（B）。

## 验证

2026-11-24 执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven -Tests CustomerDraftTest,CustomerIntegrationTest
```

隔离 PostgreSQL 16 空库执行 Flyway 至 v37，`CustomerDraftTest` 5 项、`CustomerIntegrationTest` 4 项，共 9 项通过、0 失败，BUILD SUCCESS。覆盖客户创建/搜索/外部 ID 反查/版本冲突、会员绑定、权益发放、重复核销幂等、过期/停用/归档/超次拒绝、员工 403、跨公司 404 和服务进度。

未覆盖：V36 已有库升级、A/D/E 端到端联调、最终角色权限、真实商城接口。
