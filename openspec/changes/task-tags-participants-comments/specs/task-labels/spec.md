## ADDED Requirements

### Requirement: 任务标签模型与单标签关联

系统 SHALL 保存标签 ID、名称、分类、颜色、公司范围、可选部门范围、创建人、状态、版本和更新时间。每项任务 SHALL 最多关联一个标签，服务端 SHALL 返回已存储的标签颜色。

#### Scenario: 合法单标签选择

- **WHEN** 创建或修改候选选择本公司、活动且在可见部门范围内的标签
- **THEN** 系统 SHALL 保存唯一的任务标签关联
- **AND** 任务详情和列表 SHALL 返回标签 ID、名称、分类和颜色

#### Scenario: 多标签或不可见标签

- **WHEN** 客户端为同一任务提交多个标签、其他公司标签、停用标签或不在部门范围的标签
- **THEN** 系统 SHALL 拒绝请求且不改变任务关联

### Requirement: 标签维护权限与并发

系统 SHALL 仅允许创始人直接创建、更新或停用标签，并 SHALL 对更新执行版本校验。

#### Scenario: 非创始人直接修改标签

- **WHEN** 非创始人调用标签新增、更新或停用接口
- **THEN** 系统 SHALL 返回 `403 FORBIDDEN`

#### Scenario: 标签版本过期

- **WHEN** 创始人使用旧版本更新标签
- **THEN** 系统 SHALL 返回 `409 VERSION_CONFLICT`
- **AND** 标签名称、颜色、状态和更新时间保持不变
