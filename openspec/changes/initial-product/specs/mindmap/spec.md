## ADDED Requirements

### Requirement: Default navigation and quadrants
Android SHALL 默认打开首页，底栏从左往右依次为首页、公司、日志、AI地图、我的。首页 SHALL 按home-company-daily-todos规格显示事件纪、本人任务看板与独立每日事项月历；原个人重点/日志首页块移除但不删除存量数据和兼容路由。

#### Scenario: Read company cards
- **WHEN** 任何角色打开上方两个公司区域
- **THEN** 内容保持只读，允许写入独立的私人备注；维护通过独立授权入口进行

#### Scenario: Edit personal content
- **WHEN** 本人点击下方重点或日志
- **THEN** 进入对应编辑页，重点最多置顶十条，日志遵守提交及修订规则

### Requirement: Private notes and panel traversal
系统 SHALL 提供头像、介绍、个人重点和动态时间线；上级穿透 SHALL 明确显示被查看人且不暴露密码、私人备注或未提交草稿。

#### Scenario: Keep notes private
- **WHEN** 上级穿透员工面板
- **THEN** 只返回授权业务信息，不返回该员工的私人备注

#### Scenario: Show dispatch affordance
- **WHEN** 用户有任务派发资格
- **THEN** 导图右下角显示不遮挡底栏的圆形加号，无资格用户不显示
