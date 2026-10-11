## Why

项目已有 OpenSpec，但配置未覆盖当前分工、分层、迁移、验收和追溯约束，且本机缺少 CLI。补齐共享配置，让组员 B 按现有流程开发并保持团队边界。

## What Changes

- 安装与仓库技能一致的 CLI 1.14.1，扩充共享 context/rules。
- 修正配置中的导航方向，区分现有技术栈与规划。
- 增加使用维护说明，并补齐既有 AI 地图主规格 Purpose 占位说明以通过严格校验。
- 优先级：维护；负责人：组员 B；Issue/Sprint：待关联，不编造编号。

## Capabilities

无产品行为变更；本次为工具配置和文档维护，设置 skip_specs: true，不新增产品 delta spec。

## Impact

影响 openspec/config.yaml、规范用途说明及 docs/openspec-guide.md；不修改后端、Flutter、数据库迁移或现有产品需求。验收为 CLI 可执行、完整严格校验通过、artifact instructions 实际加载 context/rules。
