## 1. Planning
- [x] 1.1 现状梳理（design §1）并经用户确认
- [x] 1.2 输出《多创始人审核规则与权限矩阵》（design §2；用户 2026-11-01 确认直接实施，不等待甲方）
- [x] 1.3 开工前 fetch，确认 V28 未被占用，`openspec.cmd validate --all --strict` 通过
## 2. Backend
- [x] 2.1 V28 迁移：约束扩展、存量失效待审兼容处理（未加 reviewer_selected 列：审核人更换已由 REVIEW_REVIEWER_CHANGED 审计记录，无读取方）
- [x] 2.2 路由：FOUNDER_PEER 分配、单创始人免审、无审核人 REVIEW_UNASSIGNED 通知
- [x] 2.3 决定：FOUNDER_PEER 复核、PENDING 守卫与影响行数校验
- [x] 2.4 审核人候选与更换接口（JavaDoc、OpenApi schema）
- [x] 2.5 审核模块 `reconcile` 在 USER/REVIEWER 变更应用的同一事务内复核其他待审申请（经审核应用链调用，组织模块不直接写审核表）
- [x] 2.6 解除单创始人：legacy 场景 V4、annual 场景 V2 新增第二位创始人与账号；Mock 同步；场景文档账号表更新
## 3. Mobile
- [x] 3.1 Repository / Mock：候选、更换接口与新字段
- [x] 3.2 审核详情模式文案与更换审核人弹窗（加载/空/失败）
- [x] 3.3 REVIEW_UNASSIGNED 通知文案与跳转；管理页规则文案
## 4. Docs
- [x] 4.1 backend-interface.md、openapi.json、mobile-openapi-contract.yaml、database-schema.md、member-b-review.md
- [ ] 4.2 更新方案.md 创始人条款、主规格 collaboration-backend 与 annual-scenario-rebuild.md 账号表
## 5. Verification
- [x] 5.1 后端单元与集成测试（design §9）通过；`scripts/test-backend.ps1` 全量仍有与基线一致的既有失败
- [x] 5.2 V28 升级测试
- [x] 5.3 Flutter analyze 与相关测试
- [x] 5.4 验收记录写入 docs，PR 正文附证据与风险

备注（2026-11-01）：4.2 已更新方案.md 与场景账号文档，主规格 collaboration-backend 待归档时同步。5.1 全量后端存在与基线 origin/main 相同的既有失败，本变更相关测试全部通过，见 docs/zhw-week7-validation.md。真机手工走查未执行。

## 6. 2026-11-06 用户规则修订（取代创始人互审）
- [x] 6.1 创始人权限内新申请免审；部门经理仅由直属上级审核，其他创始人不可代审。
- [x] 6.2 新增前向迁移作废旧 FOUNDER_PEER 待审申请及步骤，保留已决历史、审计和通知；禁止恢复或审批旧候选。
- [x] 6.3 同步客户端/Mock、契约和现有规格，不提供互审换人入口。
- [ ] 6.4 验证多创始人直属路由、越权、重复决定、迁移升级及端到端回归；记录实际结果。

2026-11-06：6.1–6.3已实施并定向验证。后端31项通过（MultiFounderReviewIntegrationTest、FounderReviewRetirementMigrationTest、MobileP0MigrationUpgradeTest、BackendIntegrationTest），客户端审核/通知5项通过，OpenSpec46项通过。6.4全量仍未通过：首次后端510项含2失败/2错误/1跳过；2项本次夹具/迁移期望失败已修正并由31项专项复验通过，年度场景V1空reviewer_id的2错误未处理，未重跑全仓。Flutter安装main已有lunar依赖后无error，仍有其他页面3warning/9info。证据见output/founder-rule-focused3.log、founder-rule-flutter-final.log、founder-rule-spec-final.log、founder-rule-backend2.log、founder-rule-analyze2.log。未对展示库执行迁移、未真机验收、未提交或推送；个人.idea和指标混合改动仍保留，按仓库自动推送规则停止发布。关联既有multi-founder-review主题（PR #57历史上下文），本轮未发送远端消息。

2026-11-11 复验：后端专项31项0失败0错误且构建成功，Flutter审核/通知5项全部通过，OpenSpec严格校验46项通过。证据：output/founder-rule-recheck-20261111.log、output/founder-rule-flutter-20261111.log；全仓年度初始化问题跟踪 #73，本次未重跑全仓，展示库未执行V31。按用户明确授权提交推送，个人配置和指标排除；关联 #56。
