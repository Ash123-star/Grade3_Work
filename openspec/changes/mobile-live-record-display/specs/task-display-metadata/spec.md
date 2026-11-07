## ADDED Requirements

### Requirement: Consistent task display metadata
任务读写链路SHALL保留参与人ID用于业务逻辑，使用姓名与中文标签用于展示。故事优先级P1，范围包含新建、已创建Mock任务及HTTP字段适配。

#### Scenario: Task dispatch and readback
- **WHEN** 用户选择研发标签和有姓名的参与人并派发任务
- **THEN** 列表、详情和编辑上下文显示中文标签及对应姓名，不显示department-research或u1作为名称

#### Scenario: Missing display fields or unknown identities
- **WHEN** 旧Mock任务缺少名称或HTTP返回仅含ID
- **THEN** Mock从现有组织记录精确按ID补齐；HTTP保留实际姓名，缺失时明确提示，不编造姓名或额外查询越权数据
