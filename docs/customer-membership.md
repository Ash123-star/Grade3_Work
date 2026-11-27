# 二期客户、会员与权益（C）

本模块是二期 C 的后端主数据：客户档案、统一客户 ID、商城会员、年卡/权益、核销和服务进度。入口 `/api/customers`，首版仅 ACTIVE ADMIN；角色权限待 B 与甲方确认后集中调整。A 的 CRM 界面、D 的线下业务和 E 的商城同步通过客户 ID/外部 ID 关联，各自不复制客户表。

## 数据

- `customers`：个人/企业客户，`cus_` 统一 ID；`external_id` 为公司内唯一商城外部 ID，可空。支持同公司在职负责人、企业联系人及版本控制；个人客户不保留企业联系人。
- `customer_memberships`：每客户一条商城会员绑定（商城会员 ID、等级、加入/到期、状态）。
- `customer_benefits`：每客户多条年卡/权益，带有效期和可选次数上限。
- `customer_benefit_redemptions`：核销记录，`(company, benefit, event_key)` 唯一，与权益使用同一公司和客户；保留首次核销的 `used/remaining`。
- `customer_progress`：会员服务阶段和说明。
- 仓库 Flyway：`V37__customer_membership.sql`、`V38__customer_redemption_receipts.sql`、`V43__customer_profile_contacts.sql`。V43 保留已有客户及关联资料。若部署环境使用外部迁移目录，以该库历史为准，只能追加迁移，不重排已应用版本。如某环境已单独应用 V37 且写入核销记录，V38 会停止并保留数据；需先确认历史回执处理方案，不要清空核销表。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/customers` | 分页搜索客户；search/kind/cursor/limit |
| POST | `/api/customers` | 新建个人/企业客户；正式客户端提交 `Idempotency-Key`，疑似重复由操作人确认后以同键重新提交 `confirmDuplicate=true` |
| GET | `/api/customers/external/{externalId}` | 商城外部 ID 反查统一客户 |
| GET | `/api/customers/{id}` | 详情：customer/membership/benefits/progress |
| PUT | `/api/customers/{id}` | 更新档案，带 version；省略负责人/联系人字段保留旧值，显式清空时传 `ownerId: null` 或 `contacts: []` |
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
- C 不实现商城拉取、订单金额、经营概览（E），不实现下文的线下业务（D），不实现 CRM 页面（A），不含合同/员工档案（B）。

## 二期 D：线下业务与服务交付

使用本模块的 `customerId` 和现有组织用户 ID 关联 `V41` 的独立线下记录，不写 `customer_progress` 或权益核销。正式 Flutter 从「公司 → 客户目录」进入，可切换客户目录和员工视角，均以同一个业务 ID 打开详情。客户档案、会员、权益核销、进度和商城订单也在同一入口，分别由原业务服务处理。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/offline-deliveries?customerId=…` 或 `?employeeId=…` | 两种筛选互斥，员工匹配负责人或参与人员；`pendingOnly=true` 只查待交付，含活动未结束和已结束两类 |
| GET | `/api/offline-deliveries/employees` | `search` 按姓名，`activeOnly` 默认 true；false 还包含已停用人员，用于查询历史；仅返回 `id/name/status` |
| GET | `/api/offline-deliveries/{id}` | 正式记录、版本、结束/交付时间及可选 `pendingReview`；摘要仅返回操作与查看/撤回能力，不返回候选 |
| POST | `/api/offline-deliveries` | `customerId/kind/title/businessDate/ownerId/participants`；201 返回 `id/version` |
| POST | `/api/offline-deliveries/{id}/changes` | `action/version/reason` 必填；`EDIT` 还须完整提供 `kind/title/businessDate/ownerId/participants`；202 返回 `id/reviewId/version/status` |
| POST | `/api/reviews/{id}/withdraw-offline` | 无请求体、版本或幂等键；原申请人或清理失权申请的同公司管理员可撤回，重放返回 `SUPERSEDED` |

分页接受非负偏移 `cursor` 和 `limit`（1–100），返回 `items/total/nextCursor`，末页为空游标。`kind` 为 `PERFORMANCE`（赛演）、`PRIVATE_BANQUET`（私宴）、`COMPANY_VISIT`（企业参访）或 `SALON`（沙龙）；业务日期为 `YYYY-MM-DD`。初始 `SCHEDULED/PENDING`；`END_ACTIVITY` 批准后为 `ENDED/PENDING`；该状态下才可申请 `CONFIRM_DELIVERY`，批准后为 `ENDED/DELIVERED`。申请不改正式版本或值，交付后仍可申请修改资料，不可修改类型或回退状态。

登记和变更必须携带 1–128 位 `Idempotency-Key`；公司和操作者内同键同规范化输入返回原回执，同键异输入返回 409。当前 ACTIVE、已改密的同公司 ADMIN 才能操作；新关联员工必须是本公司在职人员，归档客户仅可查看。跨公司对象 404，角色或当前审核资格不符 403，无效字段/员工 400，旧版本、重复待审或非法状态 409。复用 `/api/reviews/{id}/decision`（`expectedVersion/approve/reason`），仅当前独立直属管理员可决定，驳回须理由；无合格审核人时保持待审，申请人可在关系修复后重新分配或撤回。

## 验证

2026-11-26 在 Windows、Java 21 和隔离 PostgreSQL 16.15 上执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -Tests CustomerDraftTest,CustomerIntegrationTest,CustomerMigrationUpgradeTest
```

12 项通过，0 失败，BUILD SUCCESS。覆盖客户与会员基础接口、隔离空库及有数据的 V36 库升级至 V38、同键并发仅扣一次、后续核销和状态变化不改写首次回执、跨客户与跨公司核销拒绝，以及 V37 已有核销时安全停止升级。

2026-11-27 整合候选：隔离 PostgreSQL 的七组受影响后端测试共 41 项通过，覆盖 V41 旧数据升级、档案与企业联系人、权益核销、线下交付及商城关联。Flutter 正式配置 3 项通过，验证客户维护、核销后刷新次数、关联商城和线下记录；为客户端契约夹具。390px Flutter Web 连接真实隔离 API，验证登录、公司入口、建档及回读、同名重复提示。商城使用合成导入文件在真实隔离 API 上验证成功，未验证供应商连接。共享环境、最终岗位授权和真机仍待验收。D 的验收范围见 [CRM 任务](../openspec/changes/crm-customer-workspace/tasks.md)。
