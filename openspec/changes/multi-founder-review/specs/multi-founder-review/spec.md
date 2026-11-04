## ADDED Requirements

### Requirement: Founder peer review
Should：创始人发起的非 `MEMBERSHIP` 关键变更，当同公司存在至少一位其他有效创始人时，系统 SHALL 以 `FOUNDER_PEER` 模式分配且仅分配一个由其他有效创始人承担的待审步骤，不得自动生效。同公司没有其他有效创始人时 SHALL 维持现有 `FOUNDER_EXEMPT` 原子免审。apply MUST 仍按申请人业务权限与目标版本校验。

#### Scenario: Peer founder approves
- **WHEN** 公司有创始人 A、B，A 提交任务修订，B 以当前 expectedVersion 批准
- **THEN** 申请 SHALL 生效，`decision_source=FOUNDER_PEER`，写入审计并通知 A；A 提交时 B 收到 `REVIEW_PENDING`

#### Scenario: Single founder keeps exemption
- **WHEN** 公司仅有一位有效创始人，该创始人提交其权限内的修改
- **THEN** 申请 SHALL 在同一事务内以 `FOUNDER_EXEMPT` 生效，不产生人工步骤

#### Scenario: Founder self review rejected
- **WHEN** 创始人 A 对自己的 `FOUNDER_PEER` 申请调用决定接口
- **THEN** 服务端 MUST 返回 403 `SELF_REVIEW`，不写任何结果

#### Scenario: Non-reviewer founder rejected
- **WHEN** 非当前审核人的创始人 C 读取或决定 A 的申请
- **THEN** 服务端 MUST 返回 403，不扩大其读取范围

### Requirement: Reviewer selection for founder peer review
申请人 SHALL 能对本人 PENDING 的 `FOUNDER_PEER` 申请从其他有效创始人中更换审核人；候选 MUST 排除申请人和失效账号。其他模式 MUST 拒绝更换审核人。更换与决定 MUST 串行，先提交者生效。

#### Scenario: Change reviewer
- **WHEN** A 将申请审核人从 B 改为 C
- **THEN** B 的步骤 SHALL 置为 SUPERSEDED，C 收到通知并可决定，B 再决定返回 403，审计记录 `REVIEW_REVIEWER_CHANGED`

#### Scenario: Invalid reviewer selection
- **WHEN** 申请人选择自己、非创始人、停用账号或其他公司用户，或对 `DIRECT_MANAGER`/`ADMIN_MEMBERSHIP` 申请调用更换接口
- **THEN** 服务端 MUST 分别返回 400 `INVALID_REVIEWER` 或 409 `REVIEWER_SELECTION_UNSUPPORTED`，原步骤不变

#### Scenario: Repeat selection is idempotent
- **WHEN** 申请人再次选择当前审核人
- **THEN** 服务端 SHALL 返回原详情，不新增步骤、审计或通知

### Requirement: Concurrent decisions apply once
审核决定与审核人更换 SHALL 锁定申请行，并以 `state/status='PENDING'` 条件更新步骤与申请；影响行数不为 1 时 MUST 返回 409 且整体回滚。

#### Scenario: Parallel approve and reselect
- **WHEN** 审核人批准与申请人更换审核人同时提交
- **THEN** 只有一个操作 SHALL 成功，另一个返回 409，业务变更、审计和 outbox 各只写一次

#### Scenario: Duplicate approval
- **WHEN** 同一审核人重复提交批准
- **THEN** 第二次 MUST 返回 409，不重复应用变更

### Requirement: Automatic reroute when reviewer becomes invalid
组织 `USER` 或 `REVIEWER` 变更使待审步骤的审核人失效（停用、角色变化或直属关系变化）时，系统 SHALL 在同一事务内作废失效步骤并按当前规则重新路由；仍无有效审核人时 SHALL 保持 PENDING 并向申请人和有效管理员发送去重的 `REVIEW_UNASSIGNED` 通知。管理员 MUST NOT 因此获得非 MEMBERSHIP 审批权。

#### Scenario: Disabled founder reviewer
- **WHEN** 管理员停用正在审核 A 申请的创始人 B，公司另有有效创始人 C
- **THEN** 申请 SHALL 自动改派给 C，C 收到 `REVIEW_PENDING`，审计记录 `REVIEW_AUTO_REROUTED`

#### Scenario: No reviewer remains
- **WHEN** 员工的直属上级被停用且未配置新上级
- **THEN** 申请 SHALL 保持 PENDING、没有可操作步骤，申请人和管理员收到一次 `REVIEW_UNASSIGNED`，管理员调用决定接口返回 403

#### Scenario: Organization change failure
- **WHEN** 组织变更因版本冲突失败
- **THEN** 审核步骤 MUST 不发生任何改派，通知不写入

### Requirement: Legacy pending compatibility
V28 迁移 SHALL 保留所有已决定记录（含历史 `FOUNDER_EXEMPT`），只对审核人已失效的存量 PENDING 申请作废步骤并按新规则重新分配；迁移 MUST NOT 自动应用任何历史候选或把待审改为免审。

#### Scenario: Upgrade with stale pending step
- **WHEN** 升级前存在审核人已停用的待审申请
- **THEN** 升级后旧步骤为 SUPERSEDED，新步骤指向当前有效审核人或保持无步骤并产生一次 `REVIEW_UNASSIGNED`，目标业务对象版本不变

#### Scenario: Founder left alone after upgrade
- **WHEN** 公司只剩一位有效创始人且其仍有 `FOUNDER_PEER` 待审申请
- **THEN** 申请 SHALL 保持 PENDING，申请人显式 reroute 后按权限与版本校验原子免审

### Requirement: Client review display consistency
移动端审核详情 SHALL 按 `approval_mode` 显示“直属上级审核/创始人互审/管理员确认”，仅在 `reviewer_selectable=true` 时提供更换审核人入口，并处理加载、空候选和失败重试；`REVIEW_UNASSIGNED` 通知 SHALL 有中文文案和正确跳转。真实模式请求失败 MUST NOT 回退 Mock 成功。

#### Scenario: Selectable reviewer UI
- **WHEN** 创始人打开本人 FOUNDER_PEER 待审申请
- **THEN** 页面 SHALL 显示当前审核人与“更换审核人”，提交失败时提示错误并保留原审核人

#### Scenario: Not selectable
- **WHEN** 员工打开直属上级审核申请
- **THEN** 页面 MUST NOT 显示更换入口
