## ADDED Requirements

### Requirement: Readable full-width month previews
月历 SHALL 使用页面安全区域全宽并保留高度约束，记录使用按格宽适配且最大10dp的紧凑字号并遵循系统字体缩放，MUST NOT 用 FittedBox 压缩文字。

#### Scenario: Long titles or crowded dates
- **WHEN** 日期包含长标题或记录超过可读轨道容量
- **THEN** 标题只显示前6个Unicode字素、严格单行且无省略号，每格按可用高度显示最多五条，点击日期可查看全部

#### Scenario: Month-only action placement
- **WHEN** 用户打开月视图
- **THEN** 创建任务恢复为有派发权限时显示的右下角悬浮按钮，“今天”位于日周月导航栏下方靠右；日视图和周视图布局保持不变

#### Scenario: Insufficient height with large text
- **WHEN** 可用高度不足容纳完整一行
- **THEN** 不挤压字号，不绘制放不下的轨道，日期入口仍可访问全部记录

### Requirement: Hierarchical sibling swipe navigation
页面 SHALL 支持底部五栏及现有同级内容平移滑动，保留原按钮、权限与状态。故事优先级P1，范围为日周月、任务分类、AI分析标签和成员面板分类。日志根页MUST NOT通过横滑打开下属日志。

#### Scenario: Interior and outer navigation
- **WHEN** 用户完成有效横滑
- **THEN** 页面随手指平移，松手后提交或回弹；优先切换内部相邻内容，内部边界交由底部相邻栏目，最外层边界不循环

#### Scenario: Invalid or unsafe navigation gesture
- **WHEN** 用户短拖、纵滑、多指操作、从屏幕边缘起滑、打开键盘或被弹窗覆盖
- **THEN** 不执行横滑导航，编辑内容和原有交互保留

#### Scenario: Logs navigate between bottom branches
- **WHEN** 任意角色在日志根页左右滑动
- **THEN** 左滑到AI地图、右滑到视图，不打开下属日志，服务端权限边界保持不变

### Requirement: Continuous member workspace paging
下属工作台 SHALL 在同一分页视口连续展示当前与相邻分类，MUST NOT 使用先将唯一页面滑空再滑入下一页的两段转场。优先级P1，范围为已有六类成员内容，不改变权限和接口。

#### Scenario: Dragging and settling between member categories
- **WHEN** 管理者拖动下属工作台并松手
- **THEN** 当前与相邻分类连续平移，原卡通背景覆盖视口，分页吸附后同步路由，已访问分类保留滚动状态

#### Scenario: Interrupted gesture or protected content
- **WHEN** 多指取消、键盘出现、弹窗遮挡或成员权限失效
- **THEN** 不提交错误分类路由，取消手势恢复已选分类，失去权限时清除受保护分页内容
