## Why

`/api/logs/subordinates`、`log_tasks` 和基础范围过滤已经存在，但列表查询仍在 Controller，保存草稿时不会先校验 `taskIds` 的任务读取范围，候选日志在审核生效时也没有重新校验申请人是否仍有任务访问权。这会使任务关联依赖数据库外键而不是业务权限。需要将日志查询和任务关联规则收敛到 `module/log`。

## What Changes

- 新增日志查询应用服务，承接本人列表和下属日志固定入口的范围、草稿私密与筛选规则。
- 对草稿保存、已提交日志修订申请和审核生效的 `taskIds` 统一校验：任务必须在申请人当前服务端读取范围内；失败不留下关联写入。
- 复用 V4 的 `log_tasks` 表和复合外键，不新建替代表；关联同步在同一事务内删除旧关系、写入新关系。
- 新增 V9 部分索引，优化公司内按负责人和业务日期查询已提交日报。
- 补充单元与集成测试，覆盖下属入口、草稿不可见、组织范围和任务关联。

## Capabilities

### New Capabilities
- `log-task-linkage`: 下属日报查询和日志任务关系的权限一致性。

### Modified Capabilities
（无。日报草稿、提交、版本和评语工作流保持变更 4 的契约。）

## Impact

- 代码：`module/log` 新增查询服务，`LogController` 委托；`LogTaskLinks` 增加基于 `TaskAccess` 的关联校验；复核生效日志修订时复用该校验。
- 数据库：V9 仅新增部分索引；继续使用 V4 `log_tasks`。
- 非目标：不实现审核链、通知投递、AI provider 或 Flutter 接口调用。
