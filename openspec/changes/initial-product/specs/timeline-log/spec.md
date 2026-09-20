## ADDED Requirements

### Requirement: Shared daily weekly monthly range
视图与日志 SHALL 共享日/周/月日期区间，默认 Asia/Shanghai、周一起算，服务端按相同边界查询日志与任务。

#### Scenario: Carry selected range
- **WHEN** 用户在视图选择一个跨月自然周后进入日志
- **THEN** 日志保留该周区间，不切回当天

#### Scenario: Handle timezone boundary
- **WHEN** UTC 时间落在本地日期边界两侧
- **THEN** 按用户业务时区归入正确的日报日期

### Requirement: Daily log lifecycle and subordinate access
日志 SHALL 支持每日一份主日报、草稿、提交、版本化修订和关联任务；查看他人日志的入口 MUST 位于日志页，且仅上级有相应数据范围。

#### Scenario: Review subordinate logs
- **WHEN** 管理者进入日志页下属日志
- **THEN** 只能选择范围内人员并读取已提交内容；已读和评语独立记录

#### Scenario: Protect drafts
- **WHEN** 上级请求未提交的员工草稿或员工请求其他人日志
- **THEN** 拒绝读取，不通过搜索或导出泄露

#### Scenario: Revise submitted log
- **WHEN** 作者修改已提交日志
- **THEN** 创建修订版本并按审核规则处理，不静默覆盖原文
