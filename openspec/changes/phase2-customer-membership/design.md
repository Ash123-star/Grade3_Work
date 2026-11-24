## Context
二期 C 负责客户、商城会员、年卡权益和服务进度。现有系统没有客户表；A 负责 CRM 界面，D 负责线下业务，E 负责商城同步，B 负责最终字段权限确认。首版需要先给出稳定的统一客户 ID 和可幂等的权益核销，避免后续模块各自建客户或重复扣次。

## Goals / Non-Goals
**Goals:**
- 个人/企业客户统一主数据，公司内唯一商城外部 ID。
- 会员绑定与年卡/权益有效期、次数上限和核销历史。
- 同一权益同一幂等键只核销一次；过期、停用、超次拒绝。
- 服务进度可追加、可回查；客户详情供 D/E 关联。

**Non-Goals:**
- 不实现商城 API 拉取、订单金额或经营概览（E）。
- 不实现线下业务表、合同、员工档案（B/D）。
- 不实现 CRM 界面（A）和角色权限细化（B）。
- 不在本批做客户合并/冲突自动合并；外部 ID 冲突返回 409 由人工确认。

## Decisions
### 1. 统一客户 ID + 外部 ID
客户 ID 使用 `cus_` + UUID；`external_id` 为公司内部分唯一索引，可空。D 保存客户 ID，E 用外部 ID 反查客户；不建立跨公司全局 ID。

### 2. 会员与权益分表
`customer_memberships` 一个客户一条商城会员绑定；`customer_benefits` 一个客户多条权益，带 `valid_from/valid_to/max_uses`。年卡作为 `ANNUAL_CARD` 权益，不在客户表硬编码有效期。

### 3. 核销以唯一键保证幂等
`customer_benefit_redemptions` 对 `(company_id,benefit_id,event_key)` 唯一。先按 key 查已有记录，命中直接返回；未命中再校验权益归属、状态、有效期和次数，插入冲突时回查。这样重试不会多扣，过期后的同键重放仍返回原结果。

### 4. 权限首版集中收口
所有 `/api/customers` 接口经 `CustomerService.admin()` 刷新 ACTIVE ADMIN 并拒绝首次改密。B 与甲方确认角色后，只需改该入口和查询范围；不向普通员工或现有管理员后台之外的角色放开。

## Risks / Trade-offs
- [权限未最终确认] → 首版只给 ADMIN；角色扩展需 B 确认后修改并补越权测试。
- [外部 ID 冲突] → 409，不自动合并客户；由人工确认。
- [核销并发] → `FOR UPDATE` 锁权益行 + 唯一索引；同一权益不同 key 的并发仍按事务串行。
- [商城字段未确认] → 只保存 `mallMemberId/level/joinedAt/expiresAt/status`；E 提供字段后扩展。

## Migration Plan
1. 新增 V37 建表与索引；不改已发布迁移。
2. 空库和升级库执行 Flyway，验证客户/会员/权益/核销外键与唯一约束。
3. 接口先仅 ADMIN；联调 A/D/E 前确认字段和权限。

## Open Questions
- 甲方最终哪些角色可看客户、金额和合同；商城外部 ID 与会员等级字段；核销事件键由谁生成。
