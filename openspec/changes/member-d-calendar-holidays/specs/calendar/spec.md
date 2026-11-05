## ADDED Requirements
### Requirement: Monthly task previews
系统 SHALL 完整显示正式任务与候选所需任务行，按2026-11-04确认要求增长周高，不以五行或+N折叠；点击日期打开完整日清单，相邻月份也可点击。
#### Scenario: Six tasks
- WHEN 某日六条任务
- THEN 六条全部显示、周高增加，打开清单仍可见六条
#### Scenario: Adjacent month
- WHEN 点击相邻月份日期
- THEN 按真实年月日显示对应任务
### Requirement: Mainland holidays
系统 SHALL 由服务端提供经校验的中国大陆节假日和调休数据，带来源与缓存状态；客户端显示星标、不可拖动，长名称可查看完整内容。
#### Scenario: Refresh
- WHEN 缓存过期且源有效
- THEN 更新内容并记录获取时间
#### Scenario: Upstream unavailable
- WHEN 源失效或数据无效
- THEN 保留旧数据并标注过期，或显示不可用；任务月历仍可用，不伪造假期
#### Scenario: Invalid year
- WHEN 年份越界
- THEN 返回400且不请求上游
