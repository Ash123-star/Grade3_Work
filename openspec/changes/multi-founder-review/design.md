# 当前决策（2026-11-06，优先于下列历史方案）
用户明确创始人之间不互审；部门经理的申请只由其当前有效直属上级审核。复用 reporting_relations + DIRECT_MANAGER，不建立创始人池或随机/按id兜底，不扩大数据范围。创始人权限内非 MEMBERSHIP 新操作同事务免审，仍校验业务权限与版本。MEMBERSHIP继续管理员确认。
用户明确旧 FOUNDER_PEER 待审全部作废并重新提交。采用新增 V31 前向迁移，将申请/待审步骤标为SUPERSEDED，保留已决记录及候选历史，不应用旧候选；写审计和通知。保留旧模式枚举供历史读取，接口不再允许新互审、换人或恢复旧待审。相比运行时惰性作废，迁移可一次关闭所有旧待审及唯一性占位，重启后状态一致。部署须停止旧版本写入后执行迁移，不能回滚到会创建互审的旧应用。

# 历史设计（已被上面的用户决定取代）

# Design

## 1. 现状梳理（任务①）

| 场景 | 当前路由 | 代码位置 |
| --- | --- | --- |
| 创始人发起非 MEMBERSHIP | 同事务 apply，`APPROVED/FOUNDER_EXEMPT`，审计 + 通知本人 | `ReviewApplicationService.create` 39-44 |
| 其他角色发起非 MEMBERSHIP | 唯一 ACTIVE、非 must_change 直属上级；汇报环或无上级 → 无步骤保持 PENDING | `route` 50-58，`ReviewRepository.directManager` |
| MEMBERSHIP（注册确认） | `role=ADMIN AND company_reviewer` 中 id 最小的一位；创始人不免审 | `membershipReviewer` |
| 决定 | 锁请求行 → 刷新 actor → 自审/状态 → expectedVersion → 步骤审核人=actor → 实时直属关系复核 → apply → 审计 + outbox | `decide` 80-105 |
| 重新路由 | 仅申请人；作废待审步骤后按当前规则路由，创始人则免审 | `reroute` 108-125 |
| 审核人失效 | 无处理；`validReviewer` 过滤后显示“未配置” | `OrganizationReviewedRevisionApplication` USER 分支 |

已有保障：数据库 `review_steps_not_self_review` CHECK、驳回必须有理由 CHECK、每个申请最多一个 PENDING 步骤的部分唯一索引（V22）、决定 outbox 去重键。

## 2. 规则与权限矩阵（任务②）

“有效创始人”定义：同公司、`role='FOUNDER'`、`status='ACTIVE'`、`NOT must_change_password`。

| 申请人 | 申请类型 | 公司其他有效创始人数 | 审核模式 | 审核人 | 申请人可更换审核人 |
| --- | --- | --- | --- | --- | --- |
| 创始人 | 非 MEMBERSHIP | ≥1 | `FOUNDER_PEER` | 默认：该创始人的直属上级若为有效创始人则取之，否则取 id 最小的其他有效创始人 | 是，仅限其他有效创始人 |
| 创始人 | 非 MEMBERSHIP | 0 | 免审 | — （`FOUNDER_EXEMPT`） | — |
| 管理员/总监/团队长/员工 | 非 MEMBERSHIP | — | `DIRECT_MANAGER`（不变） | 当前有效直属上级 | 否 |
| 任何人（待确认） | MEMBERSHIP | — | `ADMIN_MEMBERSHIP`（不变） | 管理员审核人 | 否 |

| 操作者 | 查看 | 决定 | 更换审核人 | 重新路由 |
| --- | --- | --- | --- | --- |
| 申请人 | ✔ 本人申请 | ✘（自审 403） | ✔ 仅 FOUNDER_PEER 且 PENDING | ✔ 本人 PENDING 申请 |
| 当前有效审核人 | ✔ | ✔ | ✘ | ✘ |
| 其他创始人（非当前审核人） | ✘（不扩大穿透） | ✘ | ✘ | ✘ |
| 管理员 | 仅 MEMBERSHIP 被分配者 | 仅 MEMBERSHIP | ✘ | ✘ |

约束：
- FOUNDER_PEER 决定时复核“审核人仍是有效创始人且不是申请人”；不复核直属关系。
- 创始人互审不改变 apply 的业务权限校验：apply 仍以**申请人**权限和目标版本校验（与现有直属上级模式一致）。
- 管理员不因任何兜底获得审批权（满足“不扩大既有权限”）。
- 公司变为只有一位有效创始人后，已有 FOUNDER_PEER 待审申请不自动免审，申请人可显式调用 reroute 继续（沿用现有“明确继续历史申请”语义）。

## 3. 技术路线比较

| 维度 | A. 新增 approval_mode `FOUNDER_PEER`（推荐） | B. 把创始人放进 reporting_relations，由直属上级模式处理 | C. 新建 reviewer_pool 表做通用候选池 |
| --- | --- | --- | --- |
| 正确性 | 规则显式，决定时可精确复核 | 依赖管理员手工配置“创始人互为上级”，易形成汇报环被判无审核人 | 正确但超出需求 |
| 改动面 | 1 个迁移 + review 模块 | 需改组织页面和数据，语义混淆 | 新表、新管理界面 |
| 兼容 | 旧模式不变 | 影响穿透范围（上级可看下属数据），扩大权限 | 需迁移所有路由 |
| 结论 | 采用 | 拒绝：会扩大数据范围 | 拒绝：YAGNI |

## 4. 数据与迁移（V28__multi_founder_review.sql）

1. 扩展 CHECK：`approval_mode` 增加 `FOUNDER_PEER`，`decision_source` 增加 `FOUNDER_PEER`（先按名称 DROP 再 ADD V22 的两个命名约束）。
2. 审核人是否由申请人指定由 `REVIEW_REVIEWER_CHANGED` 审计记录体现，不新增列。
3. 历史兼容（任务④）：
   - 已决定（APPROVED/REJECTED/SUPERSEDED）记录不变，含历史 `FOUNDER_EXEMPT`。
   - 存量 PENDING 且当前审核步骤已失效（审核人非 ACTIVE、must_change 或不再满足其模式规则）的申请：步骤置 `SUPERSEDED`（理由“V28 审核人失效”），并按 §2 重新分配；创始人申请且有其他有效创始人 → `FOUNDER_PEER`；仍无审核人 → 无步骤保持 PENDING，写一条 `REVIEW_UNASSIGNED` outbox（去重键 `review-migration-v24:<id>:<recipient>`）。
   - 迁移**不**自动应用任何历史候选，不把任何 PENDING 改为免审。
   - 有效步骤的存量 PENDING 不动。
4. 回滚：迁移只新增列和枚举值、修改 PENDING 步骤状态；回滚需手写反向脚本（删除列、恢复约束）且 FOUNDER_PEER 记录须先处理，PR 中注明。

## 5. 接口

| 接口 | 权限 | 请求 | 响应 / 错误 | 幂等与版本 |
| --- | --- | --- | --- | --- |
| `GET /api/reviews/{id}/reviewer-candidates` | 申请人；申请须 PENDING 且 `FOUNDER_PEER` | — | `{items:[{id,name,current}]}`；非申请人 403，模式不符 409 `REVIEWER_SELECTION_UNSUPPORTED` | 只读 |
| `POST /api/reviews/{id}/reviewer` | 同上 | `{reviewerId, expectedVersion}` | 审核详情；候选外/自己 400 `INVALID_REVIEWER`，已决 409，版本不符 409 `VERSION_CONFLICT` | 选择当前审核人返回原结果不写新步骤 |
| `GET /api/reviews/{id}`（扩展） | 不变 | — | 新增 `reviewer_selectable` | — |
| 通知 `REVIEW_UNASSIGNED` | 接收人：申请人与有效管理员 | — | 文案“有申请缺少审核人，请配置直属关系” | dedup `review-unassigned:<id>:<recipient>:<n>` |

`expectedVersion` 沿用现有审核接口语义（目标业务对象版本）。审计事件新增 `REVIEW_REVIEWER_CHANGED`、`REVIEW_AUTO_REROUTED`。

## 6. 状态、事务与并发（任务③）

- **禁止自审**：应用层 `ReviewPolicy` + 数据库 CHECK 双重保证；候选列表排除申请人。
- **并发审批**：`decide` 已 `FOR UPDATE` 锁请求；新增 `decideStep ... WHERE id=? AND state='PENDING'`、`status ... WHERE id=? AND status='PENDING'`，影响行数≠1 抛 409，保证即使未来有绕过锁的路径也只生效一次。更换审核人与决定同锁请求行，二者串行；先到者生效，后到者 409。
- **停用/改角色/改上级**：审核模块在 `USER`/`REVIEWER` 变更 apply 成功后调用内部 `reconcile`，在同一事务内（组织模块不感知审核表）：
  1. 找出该用户作为审核人、或作为申请人直属关系变化、且仍 PENDING 的申请；
  2. 对审核人已失效者作废步骤并按 §2 重新路由，写 `REVIEW_AUTO_REROUTED` 审计与新审核人 `REVIEW_PENDING` 通知；
  3. 仍无审核人者向申请人和管理员发送 `REVIEW_UNASSIGNED`。
  锁顺序：按 id 排序对其他待审申请 `FOR UPDATE SKIP LOCKED`；正被决定或改派的申请跳过，由该事务按最新关系复核，避免死锁。
- **无审核人**：`route` 返回空时，保持 PENDING 并向申请人和管理员发送 `REVIEW_UNASSIGNED`。
- **重复请求**：决定无幂等键，重复返回 409（保持现有契约）；重复选择同一审核人返回原结果。

## 7. 客户端（任务⑤）

- 审核详情（`detail_pages.dart`）：区块标题按模式显示“直属上级审核 / 创始人互审 / 管理员确认”；`reviewer_selectable=true` 时显示“更换审核人”底部弹窗，从候选接口加载，含加载、空、失败重试状态；成功后刷新详情。
- 通知：`notification_display.dart` 增加 `REVIEW_UNASSIGNED` 文案，管理员点击进入组织管理，其他角色进入审核详情。
- 规则文案：`management_page.dart` 更新为“创始人申请由其他创始人审核；仅一位创始人时免审”。
- Mock 仓库同步同一规则，真实模式失败不回退 Mock。

## 8. 公共契约协调（任务⑥）

- 迁移编号：开工前再 fetch 一次，如他人已占用 V28 则顺延，PR 合并前再次 rebase 确认。
- 共享文件：`detail_pages.dart`、`repository.dart`、`mock_repository.dart`、`OpenApi.java`、`docs/openapi.json` 改动集中、小块提交；合并冲突在本分支 rebase 解决并在 PR 记录。
- `docs/openapi.json` 由 `BackendIntegrationTest` 生成，只提交本次相关差异。
- 完成情况与成员 A（完成情况）、成员 B（多标签契约）口径冲突时，以 `docs/backend-interface.md` 为准，记录在 PR“未完成与风险”。

## 9. 测试方案

- 单元：`ReviewPolicy`/新路由决策函数——单创始人免审、多创始人分配、候选排除自己、停用候选、非法 reviewerId。
- 集成（`ReviewIntegrationTest` 新增）：
  - 两位创始人：A 发起 → B 收到 REVIEW_PENDING → B 批准 → 生效，decision_source=FOUNDER_PEER；A 决定自己的申请 403。
  - 三位创始人：A 改派给 C；B 再决定 403；C 批准成功。
  - 并发：B 批准与 A 改派同时提交，仅一个成功，另一个 409，无重复审计/outbox。
  - 停用审核人：管理员停用 B 后 A 的申请自动改派给 C 并通知；只剩 A 时保持 PENDING 并发出 REVIEW_UNASSIGNED，A 显式 reroute 后免审。
  - 员工直属上级被停用 → 无审核人通知，管理员无法决定（403）。
  - MEMBERSHIP 不受影响。
- 迁移：`MobileP0MigrationUpgradeTest` 风格新增 V28 升级测试——失效步骤被作废与重路由、已决记录不变、历史候选未应用。
- Flutter：审核详情三种模式文案、更换审核人弹窗（成功/空/失败）、REVIEW_UNASSIGNED 跳转。
- 非功能：安全（越权、自审、管理员无审批权）、可靠性（并发只生效一次、通知去重）。

## 10. 风险

- “创始人互审”改变方案.md 已写明的免审条款，用户已确认直接实施，PR 中注明。
- 场景数据新增迁移只追加第二位创始人，不改已发布场景脚本；annual V1 只接受空库，新 V2 在其后执行，需校验第一阶段数据存在且第二位创始人账号未占用，否则整批回滚。
- 自动改派在组织变更事务内执行，大量待审时延长事务；当前数据量小，接受。
