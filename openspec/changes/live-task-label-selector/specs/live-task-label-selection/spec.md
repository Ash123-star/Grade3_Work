## ADDED Requirements

### Requirement: Database-backed task label selection
P0：任务创建与含标签的编辑表单 SHALL 从当前认证Repository的task-labels资源读取选项，显示返回名称与颜色并提交真实labelId，与任务管理表的数据来源一致。真实模式 MUST 不使用固定ID/名称/颜色选项。

#### Scenario: Custom database label
- **WHEN** 服务端返回前端未知的有效标签ID、名称及颜色
- **THEN** SHALL 可选择并按真实ID提交任务，名称与任务列表返回的label一致

#### Scenario: Unavailable or empty catalog
- **WHEN** 标签仍加载、加载失败或没有有效标签
- **THEN** MUST 显示对应状态并阻止无效提交，失败时允许重试，不回退演示选项

#### Scenario: Historical disabled label
- **WHEN** 编辑任务原标签已停用或不可选
- **THEN** SHALL 显示原名称作为历史信息并要求重新选择有效标签，不能直接提交失效ID
