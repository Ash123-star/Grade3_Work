# OpenSpec 使用与维护

先读 [核心规则](../AGENTS.md#核心规则最少必要文档与-git-差异依据) 与 [协作流程](development-workflow.md)。**只有实现具体的大功能才新建 change**，且须先确认已有主规格或活动变更不能承载；小修改、配置和文档维护不创建 OpenSpec。不得为调用工具而虚构产品能力。

## 目录职责

- `config.yaml`：共享上下文和写作约束。
- `specs/`：已同步规格；不能单凭规格存在宣称实现完成。
- `changes/<change-id>/`：一个具体大功能的 proposal、design、specs、tasks；修复及后续调整复用该功能范围。
- `changes/archive/`：历史变更；仅在对应交付范围验收、规格同步后归档，不以清理目录为由归档未完成工作。

每个主题保留一个入口。设计写入 design，验收条件写入 specs，进度和未完成项写入 tasks；运行与发布方式链接已有 `docs/` 主题，不再按日期、批次新建 tracking、handoff、deployment、verification 系列。过程证据放 `output/` 或 PR 附件。

## 操作流程

1. 核对产品、代码、现有规格及 Issue，明确范围、权限、边界、优先级和验收。
2. 大功能优先复用已有 change；确需新增时编写 proposal/design/specs/tasks。规格使用 SHALL/MUST、WHEN/THEN，覆盖正常和异常场景。
3. 规划校验后实施，完成批准批次再统一验收。没有实际运行证据的任务保持未勾选，记录限制。
4. 按 Git 实际差异提交和更新 PR；验收、审阅及规格同步完成后才归档。详见 [PR 比较流程](development-workflow.md#pr-的-git-比较基线)。

```powershell
openspec.cmd list
openspec.cmd status --change <已有变更名> --json
openspec.cmd validate --all --strict
# 仅在确需为大功能新建时：
openspec.cmd new change <change-id>
```

安装或版本不匹配时参考仓库技能的 compatibility/generatedBy，核对 CLI 后再操作；Windows 可用 `npm.cmd prefix -g` 定位 `openspec.cmd`，不依赖个人机器路径。

## 范围查找

用 `openspec.cmd list` 查看活动变更及记录中的进度，再读对应 proposal/specs/tasks。不要把目录名、已勾任务数或历史通过数当作当前完成度。按业务进入：

| 主题 | 活动范围入口 |
| --- | --- |
| 产品与模块、契约 | `initial-product`、`architecture-modularization`、`api-contract-unification` |
| 移动端页面与视觉 | `mobile-page-experience-refresh`、`tuantuan-ui-migration`、`mobile-live-record-display` |
| 任务、日历、个人事项 | `calendar-task-drag-quick-create`、`home-company-daily-todos`；另见 [任务发布](task-lifecycle-release.md)、[月历发布](calendar-task-drag-release.md) |
| 认证、组织与审核 | `member-b-week6-permissions`；另见 [分工](mvp-team-division.md) |
| AI | `ai-work-assistant`；另见 [API](ai-work-assistant-api.md)、[部署](ai-work-assistant-deployment.md)、[地图运维](ai-map-operations.md) |

旧的小改动 change 暂保留其有效验收和未完成任务，不作为新建先例；后续若并入大功能，必须迁移唯一要求、保留未完成状态、更新引用后再删除，不假称已完成归档。

## 配置维护历史限制

2026-10-11工作流初始化、2026-10-16 #18合并复查的CLI加载/严格校验证据属于当时版本；原`configure-project-workflow`配置型change已并入本指南、AGENTS和共享config，不作为产品能力保留。共享四种artifact指导仍应包含产品基线、模块边界、迁移及验收约束；配置维护不要求虚构delta规格。

- [ ] 原配置任务2.2中的Sprint归属及非作者审阅证据尚未核实（原关联Issue #3）；不因目录合并标为完成。旧批次的暂不推送指令不作为当前交付规则。
