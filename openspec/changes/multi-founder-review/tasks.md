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
