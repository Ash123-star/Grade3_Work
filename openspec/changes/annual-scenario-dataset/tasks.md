## 1. Planning
- [x] 1.1 核对V23结构、Mock颜色与凭据规则，关联Issue并通过规划校验
## 2. Implementation
- [x] 2.1 独立空库年度数据集及显式bootstrap配置
- [x] 2.2 人员、错位任务、日志、重点、评论/审核/附件/outbox
- [x] 2.3 云端新库切换、回滚、账号表与边界文档
## 3. Verification and delivery
- [ ] 3.1 真实数据库迁移、幂等/冲突/权限与登录验证（用户要求不执行）
- [ ] 3.2 编译和移动端联调（用户要求不执行）
- [x] 3.3 静态差异检查、提交推送和PR

用户授权将live-task-label-selector并行改动一并提交，未运行验证。已知未实现：管理者任务卡片限制为本人任务，不能用数据库重建代替。

规划：2026-10-30并入live-task-label-selector后OpenSpec严格校验43项通过。关联Issue #46。未执行编译、数据库迁移或测试。

提交a3dd1f8已推送，PR #47已创建；未合并main，云端未执行。
