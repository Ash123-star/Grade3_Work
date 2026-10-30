# Proposal

## Why
P0：真实任务创建页面仍使用前端固定标签ID和颜色，导致与任务管理表的数据库标签不一致，提交可能返回INVALID_LABEL。用户明确要求改用现有后端标签接口。

## What Changes
- 创建页通过当前Repository读取task-labels，只选择后端有效标签，提交真实ID。
- 加载、空列表、失败重试、编辑历史标签不可选均提供明确反馈并阻止无效提交。
- 使用返回名称和颜色；Mock也通过Repository提供标签列表，不在真实模式回退固定标签。

## Capabilities
### New Capabilities
- `live-task-label-selection`: 真实标签选择器。

## Impact
仅移动端创建/编辑标签字段、Mock标签资源及定向测试；后端接口和数据库不变。负责人当前Agent，Issue #46。本侧对话工作区与主线程共享，保留其他改动且不修改Git状态。
