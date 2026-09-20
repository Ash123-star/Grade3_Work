## ADDED Requirements

### Requirement: Mobile dispatch form without completion field
派发页面 SHALL 使用参考图的分组、名称、截止日期、紧急程度、进度备注和负责人字段；MUST NOT 出现完成情况列、表单项、筛选或替代状态标签。负责人选择 SHALL 限制在有权派发的在职人员集合。

#### Scenario: Create assigned task
- **WHEN** 有资格用户通过加号填写必填字段并选择主负责人
- **THEN** 创建任务和派发事件，向负责人发送站内消息

#### Scenario: Reject unauthorized dispatch
- **WHEN** 无资格用户直接请求 API 或选择范围外负责人
- **THEN** 服务端拒绝，不能仅依赖隐藏加号

### Requirement: Task events and reliable notifications
系统 SHALL 保存接收、反馈、验收、归档、转派及撤回事件，使用幂等键避免重复任务，并用事务 outbox 投递任务提醒、审批通知、日志待阅。

#### Scenario: Accept feedback
- **WHEN** 员工提交成果并由派发者验收
- **THEN** 保留事件历史供分析使用，派发界面仍不展示完成情况

#### Scenario: Retry delivery
- **WHEN** 消息投递失败后重试同一事件
- **THEN** 业务记录保持有效，重试不会生成重复的站内提醒
