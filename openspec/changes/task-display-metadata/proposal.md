## Why

派发页用中文标签映射，新建Mock任务却只保存标签与人员ID；详情/列表将ID直接当显示名称，出现department-research和u1。需修复读写链路并保留真实接口适配边界。用户同时要求延长开屏。

## What Changes

- 抽取共享标签中文映射，派发、任务列表/详情使用同一显示逻辑。
- Mock任务写入及读取补齐组织记录中的人员姓名，兼容本次会话已创建缺少显示字段的任务；不改变版本号或权限。
- HTTP适配保留服务端姓名及蛇形/驼峰字段，缺失姓名不以ID冒充；不额外请求未授权组织接口。
- 常规开屏从1280ms延长为2400ms，主要延长停留，维持入场与收尾节奏；减少动画保留180ms。

## Capabilities

### New Capabilities
- `task-display-metadata`: 标签中文与任务参与人姓名一致展示。

### Modified Capabilities
- None.

## Impact

Flutter表单、任务展示、Repository适配和Mock、开屏时长及文档；无服务端API/数据库/权限更改。P1，本地Issue docs/issues/task-display-metadata.md，远程编号未创建。HCJ混合改动保留。
