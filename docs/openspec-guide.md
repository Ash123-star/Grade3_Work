# 潘多拉 OpenSpec 使用与维护

本项目已初始化 OpenSpec，不需要重复创建另一套目录。全组共用 openspec/config.yaml、openspec/specs 和 openspec/changes。默认采用官方 spec-driven 工作流，不新增自定义 schema，也不覆盖已有 AI 技能。

## 安装和检查

本次安装 CLI 1.14.1，与仓库已有技能 generatedBy 版本一致。其他组员可执行：

```powershell
npm.cmd install --global @fission-ai/openspec@1.14.1
openspec.cmd --version
openspec.cmd list --json
openspec.cmd validate --all --strict
```

Windows 使用 .cmd 避免 PowerShell 脚本执行策略影响。若找不到命令，先执行 npm.cmd prefix -g，并把返回的全局目录加入当前终端 PATH，或使用该目录下 openspec.cmd 的绝对路径。本机安装路径为 E:/Dev/npm-global/openspec.cmd，不应作为其他成员的固定路径。

## 目录与职责

- config.yaml：团队共享上下文及 proposal/specs/design/tasks 的写作约束。
- specs：已同步的当前规格，不代表实际实现全部通过验收。
- changes/<change-id>：本次候选需求、设计和实施验证任务。
- changes/archive：历史归档；未经当前版本验证，不把旧记录作为当前通过证据。

组员 B 负责 auth、organization、review 后端及对应迁移、测试、契约示例；公共鉴权和统一契约与 E 协调，任务/日报生效规则与 C 协调，通知投递与 D 协调。配置属于全组共有规则，不能将整个仓库限制为 B 的工作区。

## 一次业务变更

先按复杂度判断是否需要 OpenSpec。新能力或涉及架构、权限/数据范围、数据库、公共接口、跨模块契约、重要业务状态变化的复杂变更按以下流程处理。简单文案/样式、小范围且不改变契约的修复、文档/规则维护、无行为变化的配置整理及仓库清理直接修改，在现有 Issue/PR 记录范围与验证，不强制新建 change 或文档；影响已有规格时同步相关内容。

1. 确定需求、范围、异常和权限，建立 Issue/看板任务，记录 Sprint 和负责人；检查现有规格和活动变更。
2. 在工作分支创建变更；优先复用适合的现有 change，避免重复启动同一项工作。
3. 完成 proposal.md、design.md、specs/<capability>/spec.md、tasks.md，再进行实现。
4. 通过相关单元、集成和异常/权限验证，记录命令、环境、结果；同步接口和迁移说明。
5. 检查差异、提交、推送、PR 与非作者审阅；归档前严格校验并同步主规格。

```powershell
openspec.cmd list
openspec.cmd new change <change-id>
openspec.cmd status --change <change-id> --json
openspec.cmd instructions proposal --change <change-id> --json
openspec.cmd instructions specs --change <change-id> --json
openspec.cmd instructions design --change <change-id> --json
openspec.cmd instructions tasks --change <change-id> --json
openspec.cmd validate <change-id> --strict
openspec.cmd validate --all --strict
```

可直接向助手说“openspec propose 描述需求”“openspec apply 变更名”“openspec archive 变更名”。仓库已有相关技能；创建提案不等于实施完成，归档不应提前执行。

没有产品行为变化的简单配置/文档维护无需 OpenSpec，不必为使用 `skip_specs` 额外创建 proposal、design、tasks。相关记录优先追加到现有通用主题文档或 Issue/PR，避免重复材料；已有活动变更仍按实际范围维护。

## 当前 B 工作入口与限制

initial-product 的 2.1—2.4 涉及认证、组织和审核；另有 architecture-modularization、api-contract-unification 等活动变更。先复核实际代码及任务证据，不能自动批量勾选。登录失败锁定、重复待审策略和层级访问规则应作为后续明确的业务变更，本次配置不实现这些功能。

配置上下文已按 AGENTS.md 使用左→右“导图、视图、日志、AI地图、我的”；方案.md 相反表述仍需 A/E 协调同步。配置是 AI 的指导信息，严格校验不是对权限、性能或所有团队约束的自动执行测试。

## 本次配置验证

日期：2026-10-11。维护分支：用户指定 lyb。初次严格校验 8 passed / 1 failed，既有 ai-map-direction-ui 的 Purpose 是归档占位文本，严格模式将其警告视为失败。仅补充用途说明，未修改产品需求和场景。

后端环境和业务测试不在本次配置验收范围；CLI 配置成功不表示组员 B 的业务完成。最终严格校验和规则加载检查结果见本次 change/tasks.md。
