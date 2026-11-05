## ADDED Requirements

### Requirement: Back button and page title share the first row
PageFrame SHALL 将返回按钮固定在顶行安全区域最左侧，将柴犬头像与可见标题组成间距6dp的紧凑组，相对完整标题栏水平居中并与返回按钮垂直居中。头像MUST NOT放在返回按钮组中，返回按钮保留至少48dp点击区域。故事优先级P1，范围为使用共享框架的二级页面。

#### Scenario: Detail and other secondary pages
- **WHEN** 用户进入日志详情、任务详情、设置、表单、列表或成员工作台
- **THEN** 可返回时返回按钮与可见标题同行，操作区独立换行，沿用原返回行为与权限

#### Scenario: Long titles and hidden titles
- **WHEN** 标题过长、页面隐藏标题或路由不可返回
- **THEN** 长标题单行省略以避免挤压按钮，隐藏标题不得重新显示，不可返回时不显示返回按钮

#### Scenario: Scrollable page header insets
- **WHEN** 顶栏随PageBody正文滚动
- **THEN** 顶栏不继承正文的左右留白，返回按钮仍位于安全区域最左侧，正文保留原16dp边距

#### Scenario: Document editing status hints
- **WHEN** 日志编辑页显示草稿、24小时内可修改或已锁定提示
- **THEN** 提示与已有保存信息合并靠左显示，不作为独立居中的顶部操作行；时间与锁定规则不变
