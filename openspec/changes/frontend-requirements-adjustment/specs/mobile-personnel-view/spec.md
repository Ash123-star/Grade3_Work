# Spec Delta

## ADDED Requirements

### Requirement: 唯一人员索引及独立任务管理

“我的” SHALL 只保留人员展示索引，移除重复的下属工作台和组织与成员索引页面及路由，保留人员详情导航。人员展示 SHALL 同时支持姓名搜索与部门筛选。独立任务管理 SHALL 展示本人参与/发布和授权下属参与/发布的全部任务，不以导图公司任务列表替代；Mock 通过上下级关系限定下属范围。

#### Scenario: 人员筛选及任务入口
- **WHEN** 管理者从我的进入人员展示或任务管理
- **THEN** 人员可按部门和姓名组合筛选，任务管理独立显示本人及下属全部任务并可切换视图和查看详情

#### Scenario: 普通员工
- **WHEN** 普通员工打开任务管理
- **THEN** 仅展示本人任务，不把全公司人员视为下属

#### Scenario: 无匹配部门成员
- **WHEN** 部门与姓名组合条件不匹配
- **THEN** 显示可调整条件的空状态，不伪造人员或任务

## Purpose

为移动端提供一个从“我的”进入的独立人员展示页面，让授权用户按组织范围查看人员、部门和工作状态，同时保留隐私边界和只读原则，满足甲方要求的飞书多维表式人员总览入口。

## ADDED Requirements

### Requirement: Personnel page entry and organization scope

Android SHALL 在“我的”页面提供独立人员页面入口。页面 SHALL 按服务端返回的组织范围展示人员，不允许通过查询参数切换到未授权公司、部门或人员。

#### Scenario: Authorized manager opens personnel page
- **WHEN** 部门老总、团队长、创始人或管理员从“我的”进入人员页面
- **THEN** 页面显示其授权范围内的人员和部门分组，并提供返回“我的”的导航

#### Scenario: Employee opens personnel page
- **WHEN** 普通员工从“我的”进入人员页面
- **THEN** 页面只显示本人及产品允许公开的组织信息，不显示无授权的下属或私人数据

#### Scenario: Unauthorized scope parameter
- **WHEN** 用户篡改部门或人员参数请求不在范围内的数据
- **THEN** 服务端返回权限拒绝，页面不显示任何越权结果

### Requirement: Personnel table fields and read-only behavior

人员页面 SHALL 以可扫描的列表或表格展示姓名/头像、所属部门、当前参与任务数、今日或本周日志状态、任务完成或延期状态，并支持进入授权的个人详情。第一版 SHALL 只读，不提供编辑、分组、拖拽或批量操作。

#### Scenario: Display personnel row
- **WHEN** 页面加载到有效人员数据
- **THEN** 每行展示姓名/头像、部门、参与任务数、日志状态和任务状态，长文本可换行且不造成横向溢出

#### Scenario: No activity data
- **WHEN** 人员没有本周日志或参与任务
- **THEN** 显示明确的空状态或零值，不使用伪造记录填充

#### Scenario: Read-only mutation attempt
- **WHEN** 用户在第一版人员页面尝试编辑部门、角色、状态或批量操作
- **THEN** 页面不提供这些控件，直接调用对应写接口时服务端返回不支持或权限拒绝

### Requirement: Personnel privacy and status freshness

人员页面 SHALL 不展示密码、手机号、私人备注、未提交草稿或未授权职业偏好。状态数据 SHALL 带有统计日期或更新时间；数据请求失败时不得显示过期数据为最新状态。

#### Scenario: Private data exclusion
- **WHEN** 授权用户查看人员页面或个人详情
- **THEN** 响应和界面均不包含密码、私人备注、未提交日志草稿和未授权敏感信息

#### Scenario: Stale or failed status
- **WHEN** 状态接口超时、失败或返回旧统计区间
- **THEN** 页面显示失败/待更新提示和统计时间，不把旧数据标记为当前实时状态
