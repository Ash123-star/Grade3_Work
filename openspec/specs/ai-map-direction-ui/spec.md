# ai-map-direction-ui Specification

## Purpose
TBD - created by archiving change ai-map-direction-ui. Update Purpose after archive.
## Requirements
### Requirement: 三个功能入口
AI 地图 SHALL 展示发展分析、堵点风险、行动规划，且不包含日周月筛选。
#### Scenario: 切换功能
- **WHEN** 用户选择任一入口
- **THEN** 显示相应内容并保留当前账号的行动草稿

### Requirement: 分析与权限
界面 SHALL 标明样例状态、区分事实与推测，并限制公司走向入口。
#### Scenario: 员工访问
- **WHEN** 员工打开发展分析
- **THEN** 仅能查看个人发展，不展示公司走向
#### Scenario: 未接入服务
- **WHEN** 使用真实模式
- **THEN** 不显示演示结论，显示分析服务待接入状态；后续双端遵循同一服务端权限及分析契约
#### Scenario: 数据不可用
- **WHEN** 演示场景为空、超时或无权限
- **THEN** 显示对应状态而不显示样例结论

### Requirement: 建议转为行动
用户 SHALL 能够添加建议到本地行动草稿，编辑和勾选行动，不自动发布任务。
#### Scenario: 重复添加
- **WHEN** 用户多次添加同一建议
- **THEN** 清单只保留一份，且明确标注本次演示的保存范围

