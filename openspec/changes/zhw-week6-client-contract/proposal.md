## Why

week6 HCJ 前端与 dc00e2b 后端有字段和流程差异，客户端需接通已存在的日志能力，并防止未支持字段被静默丢弃。用户已批准本批实施计划。

## What Changes

- 完整传递下属日志组合筛选、评论回复和提交窗口能力。
- 复用并验证现有真实 Repository、SSE 和会话隔离。
- 扩展真实 HTTP smoke，登记任务/标签及直接编辑缺口。

## Impact

影响 mobile 数据层、日志入口、接口文档、scripts/e2e-smoke.ps1；无数据库迁移或服务端业务修改。关联远端 Issue #32 与 Draft PR #33，本地范围记录见 docs/issues/zhw-week6-client-contract.md。
