## ADDED Requirements

### Requirement: Screenshot repair visual layers

客户端 SHALL 使用本地无文字皮肤作为可见卡片主体背景，以中心切片保持边框比例，由代码渲染真实文字、状态和操作，MUST 保持五栏导航、数据权限、错误恢复和人工确认规则。

#### Scenario: Compact dashboard and aligned actions

- **WHEN** 用户查看导图、任务详情或 AI 页面
- **THEN** 欢迎区角落装饰与卡片叠层，四象限图标与标题并排，消息/更多在滚动头部右对齐且不占用额外空白行；AI 首页使用下述精简布局

### Requirement: Simplified AI analysis entry

优先级 Should，范围为 Flutter 正式与演示 AI 首页。页面 SHALL 在顶部展示发展分析/堵点风险/行动规划三个 Tab 与对应内容，唯一“开始分析”按钮 SHALL 固定在内容区底部、五栏导航上方，滚动内容不得遮挡按钮。页面 MUST 移除“把下一步想清楚”整张欢迎卡及“点击开始分析，基于已有任务…”空状态说明；同时移除顶部大脑、建议草稿、用量、刷新/重置、范围与日期周期筛选、整个优先三件事板块、打开工作关系图入口与来源范围说明。

#### Scenario: Analyze and switch tabs

- **WHEN** 已授权用户进入 AI 首页并点击开始分析
- **THEN** 正式模式沿用当天/day 请求与既有服务端权限，完成后按 Tab 展示分析、风险和可人工确认的行动；演示模式只刷新带演示标记的数据，不派发正式任务

#### Scenario: Empty, failed or unauthorized analysis

- **WHEN** 没有分析结果、请求失败、生成进行中或账号失去权限
- **THEN** 已授权用户仍能看到底部开始分析和顶部三个 Tab，生成中禁止重复提交，失败保留明确错误与恢复操作，失权清理受保护数据；页面在 360dp 与 1.5 倍字体下可读且不横向溢出

#### Scenario: Decorative asset failure

- **WHEN** 装饰素材路径无效或图片解码失败
- **THEN** 组件保留代码表面、真实文字、操作和语义，装饰不拦截触摸

### Requirement: Distinct filters and grouped destinations

客户端 SHALL 为通知及其他筛选提供醒目的橙色选中态、勾选标记、柔和边界；我的页 SHALL 使用有纹理的功能入口与明确按钮容器，分组标题与按钮可区分。

#### Scenario: Filter and open a destination

- **WHEN** 用户切换未读/类型筛选或点击设置/帮助/管理入口
- **THEN** 数据筛选和既有路由保持有效，选中标记可辨识，触控区域至少 48dp

#### Scenario: Large text and no permission

- **WHEN** 字体放大为 1.5 倍或账号无管理权限
- **THEN** 容器自然增高且不横向溢出，未授权入口遵守原有权限规则

### Requirement: Readable month previews

月历 SHALL 保持七列日期结构、屏幕内七列等分宽度和真实摘要，每天最多两条预览，超出显示 +N；完整当天列表 SHALL 保持可访问。

#### Scenario: Long titles and overflow records

- **WHEN** 窄屏或放大字体下某日有三条以上长标题记录
- **THEN** 月历无需横向滑动即可完整显示周一至周日，记录使用纯颜色标签和任/日类型标记、不套用素材皮肤，标题单行省略；日期与 +N 共用顶部行，单元高度根据可读文字计算并接近列宽的 1.4–1.8 倍，大字体允许增加至 2 倍，点击日期打开全部记录

### Requirement: Local tuantuan visual assets

客户端 SHALL 从本地 `assets/generated_ui/` 加载用户提供的角色、业务图标、背景和裁剪后的装饰素材，禁止运行时请求外部图片。

#### Scenario: Offline asset loading

- **WHEN** 用户打开导图、视图或日志页面且设备无网络
- **THEN** 页面仍能加载角色、图标、背景和装饰素材，业务请求失败时只显示真实错误状态

### Requirement: Code-rendered interactive components

卡片、弹窗、底部弹层、Toast 和图表 SHALL 由 Flutter 代码渲染真实文字和交互，图片可作为无文字皮肤或插画内容；月历单元内的记录 SHALL 只使用代码颜色标签和单行标题简写，不显示类型前缀或类型提示。

#### Scenario: Compact monthly record labels

- **WHEN** 用户查看有任务和日志的月历日期
- **THEN** 每条记录以类型颜色区分并显示可读标题简写，月历不显示“任/日”字样或额外类型提示，超出两条时日期行显示 `+N`

#### Scenario: Accessible component states

- **WHEN** 用户使用大字体、TalkBack、加载、失败、成功或无权限状态
- **THEN** 组件保留真实文字、语义、操作和恢复路径，不依赖图片中的占位文字

### Requirement: Tuantuan page hierarchy

导图、视图、日志和我的页面 SHALL 使用统一的奶油纸张背景、圆角卡片、彩色图标托盘、角色状态和轻量装饰，同时保留既有导航、接口和权限规则。

#### Scenario: Narrow screen and large text

- **WHEN** 屏幕宽度为 360dp 或字体缩放为 1.5 倍
- **THEN** 页面不横向溢出，核心标题和操作可读，装饰不覆盖业务内容

### Requirement: Complete page asset coverage and rounded display font

客户端 SHALL 在所有用户可见页面和状态接入可见本地 UI 素材，并 SHALL 在已有主标题、重点分区和核心数字使用 GenSen Rounded TW 离线粗圆体；正文、辅助和权限文案 MUST 保持可读。

#### Scenario: Every route and overlay

- **WHEN** 用户打开任何导航、详情、表单、辅助、登录、会话恢复页面或弹窗与底部弹层
- **THEN** 实际渲染包含相应本地页面或组件素材，文字和交互由 Flutter 实现，逐路由验收记录覆盖结果

#### Scenario: Offline and unavailable decoration

- **WHEN** 设备离线、素材缺失或字体缩放至 1.5 倍
- **THEN** 标题字体由本地文件加载，素材缺失保留代码表面和全部操作，内容不溢出，状态与数据权限仍生效

### Requirement: Pandora icon and startup animation

客户端 SHALL 使用产品提供的潘多拉图标作为 Android 启动器图标和 Flutter 开屏主体，并 SHALL 在原生启动占位与 Flutter 首帧之间保持奶油纸张主题的一致性。

#### Scenario: Normal startup

- **WHEN** 用户启动应用
- **THEN** 原生启动窗口显示奶油纸色背景和潘多拉图标，Flutter 首帧以淡入、缩放和柔和光晕完成交接，随后进入既有会话恢复或登录流程

#### Scenario: Reduced motion and offline asset loading

- **WHEN** 用户启用减少动画或设备离线
- **THEN** 开屏跳过动态缩放并仍显示本地图标，动画结束后不阻塞路由、会话恢复或错误状态
