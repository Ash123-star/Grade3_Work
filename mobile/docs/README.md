# 移动端文档入口

先读根目录 [方案](../../方案.md)、[AGENTS.md](../../AGENTS.md) 和 [移动端运行说明](../README.md)。当前需求以产品基线及相关 OpenSpec 为准，行为以源码和实际接口核对；旧批次通过结果不能替代当前验收。

| 需要了解 | 阅读位置 |
| --- | --- |
| 视觉规范与素材规则 | [UI 设计基线](tuantuan-ui-design-system.md)、[品牌开屏](brand-splash-design.md)、[任务表格](task-management-ui-direction.md) |
| HTTP 接入与权限边界 | [客户端契约入口](API_CONTRACT.md)、[页面接口矩阵](api-surface-coverage.md) |
| 当前接口实现与待验收 | [P0 状态](../../docs/mobile-p0-implementation-status.md)、[剩余接口状态](../../docs/mobile-remaining-api-implementation-status.md)、[缺口跟踪](../../docs/backend-interface-gaps.md) |
| 最新真实联调结果与失败项 | [2026-10-30 联调记录](../../docs/frontend-backend-integration-validation-2026-10-30.md) |
| 草稿加密、身份恢复与设备限制 | [本地状态验证](secure-local-state-verification.md) |
| Windows 环境修复依据 | [启动修复记录](windows-startup-repair-verification.md) |
| 正在进行的范围和任务 | [OpenSpec 变更](../../openspec/changes/)；具体 change 的 design/specs/tasks |

`week5-ui-adjustment.md`、`calendar-task-view-2026-10-18.md` 仍被未完成 OpenSpec 引用，保留其限定批次证据；其日期与 Mock/设备限制不得省略。`backend-contract-gaps-mobile-page-experience-refresh.md` 保留详细场景，接口是否已实现须同时查上表最新状态。

历史阶段 0/1/3 方案、旧交付记录、旧主题截图、八屏示意板及旧页面原型已从当前树清理；引用到这些历史材料的链接固定到清理前提交，不能作为现行设计入口。必要的验收结论和未解决风险保留在最新联调记录与 OpenSpec，不把删附件解释为问题已解决。

后续截图与临时记录放根目录 `output/`，文档只记录命令、明确退出码、环境、结果和限制。需要版本化的验收图片应随对应 PR 提供，避免重新累积到 `docs/evidence/` 或 `docs/screenshots/`。
