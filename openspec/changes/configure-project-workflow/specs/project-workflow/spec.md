## ADDED Requirements

### Requirement: 共享项目工作流配置
项目 SHALL 使用 openspec/config.yaml 为团队工具提供统一的产品基线、模块边界、迁移和验收约束，且不得将规划内容表述为已实现能力。

#### Scenario: 加载变更指导
- **WHEN** 团队成员为 proposal、design、specs 或 tasks 加载 OpenSpec 指导
- **THEN** 指导包含共享项目上下文及对应 artifact 的规则
- **THEN** 客户端导航、服务端 AI 和数据库迁移约束与项目约定一致

### Requirement: 配置维护可验证
项目 SHALL 为工作流配置维护保留变更说明、验证命令与未完成事项，并通过 openspec.cmd validate --all --strict 验证规格结构。

#### Scenario: 校验工作流维护变更
- **WHEN** 成员准备提交工作流配置及文档变更
- **THEN** 变更包含至少一项带场景的 delta requirement
- **THEN** 未完成的人工确认和追溯事项保持未完成，不以规格校验替代业务验收
