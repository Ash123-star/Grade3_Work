# 当前变更范围（2026-11-06）
用户明确取消创始人互审；部门经理仅由直属上级审批。旧FOUNDER_PEER待审全部作废后由申请人重新提交。沿用本change维护，新增V31而不改V28；保留历史及已有直属关系、成员确认、并发守卫、无审核人通知。当前验收以spec及tasks第6节为准。

# 以下为已被新规则替代的历史提案

# Proposal

## Why
Should：成员 E 本周负责“多创始人审核、公共契约协调”。现状只有一条固定路由：创始人发起的非 `MEMBERSHIP` 申请一律 `FOUNDER_EXEMPT` 免审；其他申请分配给唯一直属上级；`MEMBERSHIP` 分配给 id 最小的有效管理员。现状存在以下问题：

- 同公司存在多位创始人时，任一创始人可以单方面让关键修改生效，没有任何复核，与“关键修改使用审核链、禁止自审”的目标冲突。
- 审核人被停用、改角色或调整汇报关系后，其名下的待审步骤不会处理，申请人看到“未配置审核人”，必须自己手动重新路由。
- 找不到有效审核人时，申请保持待审，但既没有审核步骤也没有任何通知，管理员无从得知需要配置直属关系。
- 决定类 UPDATE 没有状态守卫，并发正确性只依赖行锁；文档 `member-b-review.md` 与主规格 `openspec/specs/collaboration-backend` 仍描述旧的多级审核。

用户已确认的取舍（2026-11-01）：
1. 采用**创始人互审**：同公司存在其他有效创始人时，创始人的申请必须由另一位创始人审核，申请人可在候选创始人中更换审核人；仅有一位有效创始人时继续免审。
2. 审核人失效时**自动改派并通知**：同一事务内作废并重新路由；仍无审核人时通知申请人和管理员配置关系，管理员不因此获得审批权。
3. 直接按创始人互审实施，无需等待甲方确认；同步更新 `方案.md` 创始人条款。
4. 现有 schema 与代码并未限制创始人数量，“单创始人”只存在于场景数据与 Mock；由成员 E 解除：场景数据新增第二位创始人，Mock 同步。

## What Changes
- 新增审核模式 `FOUNDER_PEER` 与决定来源 `FOUNDER_PEER`（Flyway V28）。
- 创始人发起非 `MEMBERSHIP` 申请：存在其他有效创始人 → 默认分配一位，申请人可更换；不存在 → 维持 `FOUNDER_EXEMPT`。
- 新增 `GET /api/reviews/{id}/reviewer-candidates` 与 `POST /api/reviews/{id}/reviewer`（仅 `FOUNDER_PEER` 待审申请的申请人可用）。
- 组织 `USER` 变更（停用、改角色、改直属上级）生效时，同一事务内重新路由受影响的待审申请。
- 无有效审核人时向申请人和管理员发送 `REVIEW_UNASSIGNED` 通知（outbox 去重）；管理员点击进入直属汇报关系配置，申请人进入审核详情。
- 决定、改派写入加 `state/status='PENDING'` 守卫并校验影响行数；重复/并发决定只生效一次。
- 迁移对存量待审记录做兼容处理（见 design）。
- 同步审核页面、通知文案、审计、`docs/backend-interface.md`、`docs/openapi.json`、`docs/mobile-openapi-contract.yaml`、`docs/database-schema.md`、`docs/member-b-review.md`，并输出《多创始人审核规则与权限矩阵》。
- 场景数据（legacy `db/scenario` 新增 V4、annual `db/scenario-annual2026` 新增 V2）为主公司增加第二位在职创始人及测试账号；Mock 增加第二位创始人。

非目标：
- 不引入多级/会签审核，每个申请仍最多一个有效待审步骤。
- 不给管理员新增任何审批权；`MEMBERSHIP` 仍由管理员确认，不做管理员间选择。
- 不改动任务、日志、组织等模块各自的业务权限（apply 仍由所属模块按当前权限与版本校验）。
- 不处理被停用**申请人**的待审申请（保持现状，登录被拒，申请不可操作）。

## Capabilities
### New Capabilities
- `multi-founder-review`: 创始人互审、审核人选择、失效审核人自动改派、无审核人通知、并发与历史兼容。

### Modified Capabilities
- 覆盖 `mobile-page-experience-refresh` 中 “Direct-manager review and founder exemption persistence” 的创始人免审部分；归档时同步更新主规格 `collaboration-backend`。

## Impact
- 后端：`module/review/**`、`module/organization/application/OrganizationReviewedRevisionApplication.java`（经 `ReviewApi` 调用，不直接写审核表）、`OpenApi.java`/`MobileP0OpenApi.java` 中审核相关 schema、新增 `V28__multi_founder_review.sql`、测试。
- 移动端：`features/common/detail_pages.dart` 审核详情区块、`data/repositories/repository.dart` 与 `mock_repository.dart` 的审核方法、`data/models/notification_display.dart`、`features/dashboard/management_page.dart` 规则文案。
- 负责人：成员 E（zhw）。Issue / Sprint：待关联，不编造编号。
- 与成员 B 的 Flyway 迁移编号、与成员 A/B/C 的 `detail_pages.dart`、`repository.dart`、`mock_repository.dart` 存在合并冲突风险，见 design “协作与合并”。
