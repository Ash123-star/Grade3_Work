## ADDED Requirements

### Requirement: Authorized metrics
报表 SHALL 统计派发量、逾期量、按期验收率、日报提交率和待阅数，并展示区间、口径、分母与更新时间；统计和导出 MUST 使用与详情相同的数据范围。

#### Scenario: Export team report
- **WHEN** 团队长导出月报
- **THEN** 仅包含其团队可访问数据，不泄露其他部门或全公司汇总

#### Scenario: Compute from events
- **WHEN** 任务经过反馈和验收
- **THEN** 根据事件计算指标，无需在派发表格显示完成情况

### Requirement: Cartoon responsive web workspace
Web SHALL 使用独立的侧栏工作台、卡片与详情抽屉，采用卡通风格但保证正文对比度；选用 OpenMoji 的素材 MUST 记录来源、版本和 CC BY-SA 4.0 署名及修改情况。

#### Scenario: Use desktop workspace
- **WHEN** 用户通过 Web 登录
- **THEN** 默认显示导图工作台并遵循与 Android 相同的业务权限，不强制照搬手机底栏

#### Scenario: Load illustrations
- **WHEN** 页面使用 OpenMoji 插图
- **THEN** 从本地资产加载并在署名信息中提供许可和来源，不依赖远程图片热链
