## Why

企业需要统一的重点展示、任务派发、日报和上下级信息查看，减少分散表格与重复汇总。先明确双端契约、数据范围和审核规则，再开始实现。

## What Changes

- 建立 Flutter Android 与独立 Web 端，共用服务端权限。
- 提供四象限导图、日周月视图、日志、任务和站内消息。
- 实现五类角色、组织层级、分层复核和审计。
- 接入 DeepSeek 日报总结、任务建议及 AI 工作地图。
- Web 采用卡通风格，素材使用 OpenMoji 并保留 CC BY-SA 4.0 署名。

## Capabilities

### New Capabilities

- `auth-rbac`: 注册登录、组织、角色数据范围与分层复核。
- `mindmap`: 默认导图、四象限、个人面板与私人备注。
- `timeline-log`: 日周月联动、日志提交及上级查看。
- `task-dispatch`: 任务派发、人员选择、流转和站内通知。
- `ai-map`: DeepSeek 总结、任务建议与可操作工作地图。
- `analytics-web`: 报表、权限一致的 Web 卡通工作台。

### Modified Capabilities

无，当前为空项目。

## Impact

新增 mobile、web、server、deploy 等后续工程；本变更覆盖数据库、REST 契约、消息投递、审核服务及 AI 适配器。所有实现尚待 tasks 完成，不涉及既有系统迁移。
