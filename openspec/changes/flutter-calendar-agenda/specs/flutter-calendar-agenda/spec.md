## ADDED Requirements
### Requirement: Compact page chrome
所有页面 SHALL 删除顶部重复页面名称，保留返回和业务操作。
#### Scenario: Main and secondary pages
- **WHEN** 用户打开页面
- **THEN** 顶部不渲染页名，存在的返回和操作仍可用且随内容滚动，无操作及返回时移除工具栏

### Requirement: Daily agenda
日视图 SHALL 以列表显示选日全部任务和日志，使用真实时间和既有详情入口。
#### Scenario: Read and edit
- **WHEN** 用户点击列表记录
- **THEN** 打开对应详情，并沿用权限与版本规则提供编辑路径
#### Scenario: Empty or failed query
- **WHEN** 没有记录或查询失败包括 403
- **THEN** 显示真实空状态或错误重试，保留日期筛选，不以样例替代

### Requirement: Whole week overview
周视图 SHALL 纵向排列周一到周日七行摘要，同时展示且无内部滑动；每日记录过多时提供全量入口。
#### Scenario: Dense week on narrow screen
- **WHEN** 用户在 360dp 和放大字号查看一周
- **THEN** 七日均展示且无横向溢出，点击日期可查看全部记录

### Requirement: Bounded month entries
月历 SHALL 在单元格显示最多两条彩色简写及剩余数量，文字同时区分任务和日志。
#### Scenario: More than two entries
- **WHEN** 某日存在超过两条记录
- **THEN** 不撑破单元格，显示 +N，点击日期可查看完整列表并打开具体记录
#### Scenario: No records and month boundary
- **WHEN** 日期没有记录或用户切换月份
- **THEN** 空日不编造内容，跨月空格不显示未查询月份记录

最新视觉要求：周视图纵向七行，记录胶囊宽度 156dp，不铺满页面；月历无表格直线边框，圆角日期格与留白，保留两条预览、+N 和当天详情。顶部操作随内容滚动。
