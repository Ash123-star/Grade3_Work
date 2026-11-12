# Proposal

## Why

2026-11-11 用户确认 Web 仅供 ADMIN 使用，负责员工录入、直接创建员工账号和公司十大重要事项维护；完整网页版不在交付范围。

## What Changes

- P0：管理员直接开通 ACTIVE/EMPLOYEE 账号，首次登录强制改密，保留脱敏审计；公开注册保持原规则。
- P0：员工目录、姓名与部门修改及停用申请；公司重要事项新增、修改、排序、撤下申请，复用独立审核。
- P0：Vue 默认入口切换简易后台，旧 AI 源码保留但不出现在后台导航。
- 本地运行并提供云端部署说明；不操作现有云服务器，不制作完整日志/任务/报表/AI Web。

## Capabilities

### New Capabilities
- `admin-simple-console`：管理员员工账号开通、员工维护和公司重要事项管理。

### Modified Capabilities
无。既有公开注册、Android 和独立审核契约不变。

## Impact

- web 新入口、organization 管理员应用服务/仓储/控制器；复用 auth 密码规则和 review 审核服务。
- 新增 `/api/admin/console` 明确接口，不改公共安全过滤器、旧接口与历史迁移；每次调用由服务端检查 ADMIN 和公司。
- 负责人：当前开发者；Sprint：管理员后台批次；Issue #88（https://github.com/Ash123-star/Grade3_Work/issues/88）。
- 验收：真实 HTTP 创建→登录→改密、非法角色/重复账号拒绝、跨公司隔离、候选审核与浏览器链路；安全和可靠性验证。
