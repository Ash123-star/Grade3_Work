# PR #26 主线整合验收

验收日期：2026-10-22。关联 Issue #22；在独立工作区将已合并 PR #25 的主线整合到 `lyb`，保留 AI 办事工作台、已批准导航和新增日志/日历交互。

- 冲突处理：共享标签组件兼容换行；日志回复兼容父评论参数；修复字体配置；工作区访问审计使用新增 `V19__workspace_access_audit.sql`，不修改主线 V1–V18。
- 迁移工具：允许规范 V1–V18 后追加迁移，仍拒绝未知旧历史；升级测试按实际迁移数量验证。
- `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -KeepContainers`：退出码 0，完整 PostgreSQL 16/Redis 集成和 Maven 打包通过，397 项测试，0 失败、0 错误、0 跳过。
- `flutter analyze`：退出码 0，无问题。
- `flutter test --no-pub --dart-define=USE_MOCK=true --reporter expanded`：退出码 0，303 通过，1 跳过。首次未启用项目规定的 Mock 开关导致 22 项夹具失败；使用规定命令后通过。Mock/HTTP 契约验证不等同于完整真机验收。
- `openspec.cmd validate --all --strict`：32 项通过，0 失败。
- 安全与可靠性：完整后端覆盖组织范围、越权、幂等、独立审核、队列恢复和数据库升级；AI 外部模型/OCR 在集成套件中为受控供应商，不能替代真实生产材料验收。

AI change 仍有未完成验收项，自动正式写入开关默认关闭，按 Issue #24 与 OpenSpec 原任务继续跟踪。本次不归档该变更、不宣称所有产品功能完成。

本次维护者明确要求合并所有 PR，按该指示豁免非作者审阅；未将自动化验证记录为独立成员审批。运行环境未部署新迁移。
