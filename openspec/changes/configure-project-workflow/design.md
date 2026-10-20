## Context

仓库已有 spec-driven 配置、活动与归档变更、AI 工作流技能。用户授权配置并指定 lyb 分支。

## Decisions

选择扩充现有官方 config.yaml；重复 init 可能更新多工具集成文件，自定义 schema 增加维护成本，均无当前必要。CLI 固定 1.14.1，与技能生成版本一致。上下文保持全组共享，明确 B 的业务范围和 E 的公共职责。

仅用配置指导 AI，不声称 CLI 自动验证所有业务规则。保留既有规格、任务状态及技能；主规格只改 Purpose 占位说明，行为不变。

## Risks and rollback

方案的导航方向冲突仍需协调；业务和架构验证缺口不在此变更修复。Issue/Sprint 与 PR 审阅追溯仍待关联。配置可通过回退本次差异恢复；CLI 可独立卸载，不触及数据库。

## Validation

检查 --version、list --json、validate --all --strict，并使用 instructions proposal/specs/design/tasks 检查实际返回的上下文与各规则；git diff --check 验证差异格式。后端测试不适用于纯配置修改。
