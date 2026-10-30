# 手机端演示联调

## ADDED Requirements

### Requirement: 任务创建使用有效标签
客户端 MUST 从当前公司可用标签中选择 ID 并提交，服务端 SHALL 保持权限和标签有效性校验。

#### Scenario: 正常创建
- WHEN 有派发权限的用户选取可用标签和有效参与人提交任务
- THEN 服务端创建任务或待审申请，客户端显示提交结果

#### Scenario: 失效标签
- WHEN 标签已停用或不属于当前公司
- THEN 服务端拒绝请求，客户端不得把固定旧 ID 当作有效标签

### Requirement: 审批版本与人员姓名
客户端 MUST 使用申请的 `expected_version` 决定审批；任务事件及日志评论 SHALL 展示服务端人员名称。

#### Scenario: 新任务申请审批
- WHEN 直属审核人审批预期版本为 0 的创建申请
- THEN 客户端提交 `expectedVersion: 0`，服务端按权限和版本执行

#### Scenario: 无权或过期审批
- WHEN 非审核人或过期版本提交决定
- THEN 服务端拒绝且不得更改申请状态

### Requirement: 任务入口与范围
任务入口标签 MUST 一致；日志页的任务管理 SHALL 显示服务端授权的本人及下属任务，视图 SHALL 只查询本人参与任务。

#### Scenario: 管理者查看任务
- WHEN 管理者从日志页进入任务管理
- THEN 可见本人及授权下属任务

#### Scenario: 个人视图
- WHEN 用户打开视图日历
- THEN 查询使用本人参与人 ID，其他任务不进入日历
