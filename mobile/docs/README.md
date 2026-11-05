# 移动端文档索引

先读 [产品基线](../../方案.md)、[核心规则](../../AGENTS.md)、[运行说明](../README.md)。这里只索引客户端专题，全仓范围见 [总索引](../../docs/README.md)。文档优先原位维护，小修改不新建OpenSpec或会话交接。

## 现行设计与接入

| 主题 | 入口 |
| --- | --- |
| 视觉与素材 | [团团设计系统](tuantuan-ui-design-system.md)、[品牌开屏/图标](brand-splash-design.md)、[任务表格与人员目录原型](task-management-ui-direction.md) |
| 首页与个人事项 | [页面设计与卡通主题重构提案](home-daily-todos-direction.md)、[交互原型](../prototypes/home-daily-todos.html)；视觉提案待评审，导航为首页、公司、日志、AI地图、我的，默认首页 |
| APP验收对齐 | [两轮需求统一验收基准](../../docs/app-requirements-acceptance.md)；含完成情况列、五行折叠、同页人员树的最新确认及合并后回归，不代表已实现 |
| HTTP与权限 | [接入原则](API_CONTRACT.md)、[页面请求矩阵](api-surface-coverage.md)、[接口状态/待验收](../../docs/backend-interface-gaps.md) |
| 当前验证 | [统一验证入口](../../docs/backend-validation.md)；记录于2026-11-05，不外推到未验设备或供应商 |
| 活动需求 | [OpenSpec](../../openspec/changes/)中相关大功能的design/specs/tasks；旧小变更不作为新建先例 |

## 历史验收与限制

| 主题 | 记录及适用边界 |
| --- | --- |
| 草稿加密/身份恢复 | [本地状态验收](secure-local-state-verification.md)；真实设备Keystore、跨端等依记录限制核对 |
| Windows依赖 | [启动修复](windows-startup-repair-verification.md)；保留Android Studio实际启动待验项，操作命令在移动端README |
| 旧日历阶段 | [2026-10-18视图](calendar-task-view-2026-10-18.md)、[完整行发布历史](../../docs/calendar-task-drag-release.md)；2026-11-05目标恢复五行折叠，按统一验收基准重验，不继承旧布局通过结论 |
| 旧视觉阶段 | [week5调整](week5-ui-adjustment.md)；只用于相应批次追溯 |

源码和实际接口优先用于核对实现，设计存在、Mock/夹具通过或截图不能证明真实链路。新日志/截图放忽略的`output/`或PR附件，现有必要证据保留其提交和环境限制，不按批次增加另一套验证报告。
