# Spec Delta

## MODIFIED Requirements

### Requirement: 四象限横向标题与视口填充

Flutter 导图页 SHALL 保持公司重点、公司任务、个人重点、个人日志的两行两列顺序，每块图标在左、标题在右。导图页 SHALL 移除新增任务按钮、日期行和底部时间视图入口；有权限的用户 SHALL 从视图页进入新增任务。页面 SHALL 使用当前团团主题与自适应布局，保留草稿提示。

#### Scenario: 普通竖屏查看导图
- **WHEN** 用户打开普通竖屏导图页
- **THEN** 四块标题位于图标右侧，首屏不出现新增任务加号、日期行或时间视图入口，用户可通过页面滚动访问全部板块

#### Scenario: 极矮屏幕或放大字体
- **WHEN** 可用高度不足以容纳标题栏、内容区和查看全部入口
- **THEN** 页面允许纵向滚动，四块标题与入口不产生横向溢出

#### Scenario: 无派发资格
- **WHEN** 用户没有任务派发资格
- **THEN** 导图页和视图页均不显示新增任务入口，也不预留空白占位

### Requirement: 内容区域充分利用与失败状态

每块 SHALL 显示紧凑记录预览，并保留查看全部入口及加载中、空数据、失败提示。日志板块 SHALL 支持本机草稿提示，完整记录在对应列表访问。视图页 SHALL 在演示数据可用时提供每天至少十条任务供查看；月历预览受每日三条上限约束，真实数据不足时不得伪造记录。

#### Scenario: 记录多于三条
- **WHEN** 板块已加载超过三条记录
- **THEN** 板块显示紧凑预览，用户可进入查看全部访问其余授权记录

#### Scenario: 视图数据不足
- **WHEN** 真实后端返回少于十条任务
- **THEN** 页面按真实数量展示，并显示数据范围或空状态提示，不复制记录填充数量

#### Scenario: 空数据或请求失败
- **WHEN** 板块为空或记录请求失败
- **THEN** 显示暂无记录或暂时不可用提示，其他块布局和查看全部入口保持可用

### Requirement: 权限和双端数据契约保持一致

布局调整 SHALL 沿用现有授权记录接口及跨端数据范围规则；Flutter 与 Web 不因本次布局变化改变可见数据和审核版本。无派发资格的用户 SHALL 不显示派发按钮，越权请求仍由服务端拒绝。

#### Scenario: 无派发资格
- **WHEN** 用户没有派发资格
- **THEN** 不显示派发按钮，也不为该按钮保留额外底部空间，直接越权派发请求仍被拒绝

#### Scenario: 两端查询同一用户的记录
- **WHEN** Flutter 与 Web 查询相同用户和范围的数据
- **THEN** 继续使用现有授权数据及版本契约，本次仅改变 Flutter 导图的视觉布局

#### Scenario: 待确认员工访问
- **WHEN** 待确认员工打开导图或视图
- **THEN** 只能看到允许的个人状态，不能通过前端参数读取公司任务、人员或下属日志

### Requirement: 四个导图入口列表对齐与统一排版

公司重点、公司任务、个人重点、个人日志入口的 Flutter 记录列表 SHALL 使用左右 16 像素页面边距，卡片撑满页面可用宽度，所有卡片的左右边缘与搜索框对齐。卡片 SHALL 统一使用 16 像素内边距、12 像素卡片间距、相同标题样式及说明文字色，无状态数据时不保留空状态行。大屏 SHALL 沿用最大 760 像素阅读宽度，长文字和大字体 SHALL 自动换行。记录标签颜色 SHALL 来自标签契约，不得按任务/日志类型硬编码。

#### Scenario: 四个入口的长短标题
- **WHEN** 用户分别从四个导图板块进入记录列表，记录标题长短不同
- **THEN** 每张卡片均占满列表宽度，与搜索框左右边缘对齐，内边距、间距和文字样式统一

#### Scenario: 小屏和大字体
- **WHEN** 用户在小屏或放大字体下查看长标题记录
- **THEN** 标题和说明自动换行，卡片高度随内容增长，无横向溢出

#### Scenario: 标签颜色
- **WHEN** 任务或日志带有标签
- **THEN** 记录标签使用服务端返回的预设颜色，并与创建时颜色一致；缺失颜色时使用统一可读的回退色并保留标签文字

#### Scenario: 加载失败和空数据
- **WHEN** 任一列表请求失败或返回空记录
- **THEN** 继续展示现有重试或空数据提示，不渲染伪造卡片

#### Scenario: 权限与跨端契约
- **WHEN** 同一用户通过 Flutter 或 Web 查询记录，或尝试访问无权限记录
- **THEN** 沿用相同的现有授权数据和审核版本契约，越权请求仍由服务端拒绝，本次宽度调整不扩大读取范围

## ADDED Requirements

### Requirement: 导图记录分点与固定行距

导图四张卡片中的每条预览记录 SHALL 在文字前显示自定义暖色实心圆点。记录 SHALL 自上而下排列，行距固定，不因记录数量较少而拉大相邻记录间距。

#### Scenario: 多条记录预览
- **WHEN** 卡片包含两条或更多预览记录
- **THEN** 每条记录均以暖色实心圆点开头，记录从顶部向下排列且相邻行间距一致

#### Scenario: 单条或少量记录
- **WHEN** 卡片只有一条或少量记录
- **THEN** 记录行保持顶部对齐并使用相同固定行距，不在卡片剩余高度内均匀拉伸

#### Scenario: 无记录
- **WHEN** 卡片没有预览记录
- **THEN** 继续显示现有空状态文字，且不显示孤立分点

### Requirement: 主导航页面不重复显示顶部标题

五个底部导航根页面 SHALL 隐藏重复的页面名称标题行；页面内部有效标题、必要操作控件和非导航子页面的返回及标题 SHALL 保留。

#### Scenario: 打开底部导航根页面
- **WHEN** 用户打开导图、视图、日志、AI地图或我的
- **THEN** 页面顶部不显示重复的导航名称标题行，主体内容正常显示

#### Scenario: 根页面带有必要操作
- **WHEN** 主导航根页面包含必要操作控件
- **THEN** 隐藏页面名称标题后，操作控件仍可访问且不覆盖主体内容

#### Scenario: 打开子页面
- **WHEN** 用户从主导航进入有独立标题的子页面
- **THEN** 子页面标题和返回导航保持显示

### Requirement: 成员工作台身份卡配色

下属工作台的成员身份卡 SHALL 使用暖白或浅杏等与全局暖白主题一致的背景和中性暖色边线，不得使用突兀的浅蓝大面积底色。成员姓名、部门/团队、只读说明、访问锁和返回本人面板操作 SHALL 保持清楚可辨。

#### Scenario: 查看授权成员工作台
- **WHEN** 管理者打开已授权成员的工作台
- **THEN** 身份信息卡与卡通暖白页面协调，成员信息、只读属性和安全提示仍清晰可读

#### Scenario: 成员信息较长
- **WHEN** 成员姓名或组织信息较长或用户放大文字
- **THEN** 信息可换行且不遮挡锁标识或返回本人面板操作

### Requirement: 正式感登录与注册界面

移动端登录和注册页面 SHALL 采用图形主视觉区、前景表单区、登录/注册模式切换、现有功能的紧凑说明区及明确主操作，使用应用暖白与暖色主题并避免无意义的大面积留白。主视觉区 SHALL 移除通用产品名/问候/说明三行标题，采用精炼的编辑式衬线艺术标题搭配现有品牌插画。视觉调整 SHALL 保持现有字段、校验、密码可见性、部门加载/失败重试、认证路由和服务端契约不变。注册 SHALL 明确仅申请创建待确认员工，并如实说明短信验证尚未接入；不得暗示已提供第三方登录、短信验证、账号找回或其他未接入能力。

#### Scenario: 用户切换登录和注册模式
- **WHEN** 用户在登录或注册页面切换认证模式
- **THEN** 对应表单和主操作清晰显示，所有原有字段与校验行为保留

#### Scenario: 登录页空间布局
- **WHEN** 用户在常规手机竖屏查看认证页面
- **THEN** 图形主视觉、衬线艺术标题、任务/日志/日历功能提示、表单和公司账号安全说明形成连续层级，避免内容聚集在屏幕顶部而下方出现无目的的大块空白

#### Scenario: 品牌标题风格
- **WHEN** 用户打开登录或注册页面
- **THEN** 不显示“潘多拉工作台 / 欢迎回来 / 登录后继续处理团队工作”这组三行通用标题，艺术字保持可读且不挤压表单

#### Scenario: 注册部门加载失败
- **WHEN** 注册页面的部门列表加载失败
- **THEN** 继续展示明确错误和重试入口，其他表单说明可读且不伪装注册成功

#### Scenario: 不支持的认证方式
- **WHEN** 服务端没有提供 Apple、Google、短信验证码或密码找回契约
- **THEN** 页面不呈现会使用户误以为可用的对应按钮或链接

#### Scenario: 注册申请提交
- **WHEN** 用户提交有效注册申请
- **THEN** 仍只创建待确认员工并进入待确认流程，未经服务端确认不得读取公司业务数据；界面不声称短信验证已完成

### Requirement: Warm interactive colors and month record placement

Mobile interactive controls SHALL use the approved orange/warm palette instead of green, while semantic success indicators MAY remain green. Month-view record bars SHALL be positioned slightly below their current top-aligned position and the final visible bar SHALL remain above the vertical midpoint of each date cell. The registration entry SHALL use bold warm-colored text. The “我的” work-list entries SHALL render their existing cartoon PNG icons.

#### Scenario: Interactive controls
- **WHEN** a user sees a primary action, text action, selected control, or calendar navigation action
- **THEN** its interactive emphasis uses an orange or warm color, and semantic success feedback remains distinguishable

#### Scenario: Month record positioning
- **WHEN** the month grid renders one to three task bars in a date cell
- **THEN** bars sit slightly lower than before and remain entirely above the cell midpoint, without covering the date number or today decoration

#### Scenario: My page icons
- **WHEN** a user opens “我的”
- **THEN** each work/list entry displays its original local cartoon PNG icon rather than a generic replacement glyph

### Requirement: Role-based realistic mock organization

The mobile MockRepository SHALL seed at least 10 distinct accounts across the five product-defined roles. The organization tree, profiles, and account selector SHALL share consistent department, team, manager, and dispatch fields. Work records SHALL use deterministic role-appropriate content and identify comment authors and timestamps. These fixtures SHALL remain demo-only and SHALL NOT define production authorization.

#### Scenario: Switching demo roles and accounts
- **WHEN** a user selects a role or demo account in mock settings
- **THEN** the active session uses that account's matching role, name, department, team, manager context, and dispatch capability

#### Scenario: Organization hierarchy
- **WHEN** an authorized demo user opens the organization tree
- **THEN** every seeded account appears under its declared department and team, with no account silently reassigned to a default department

#### Scenario: Distinct work history
- **WHEN** a user browses demo tasks, daily logs, reviews, and comments
- **THEN** records include varied people, departments, dates, and role-appropriate copy; comments identify their author and timestamp

#### Scenario: Demo role count boundary
- **WHEN** the demo data is initialized
- **THEN** it exposes the five roles defined by the product and at least 10 distinct accounts, and does not invent additional permission roles

### Requirement: 九张批注的前端 Mock 布局

本轮 Flutter SHALL 使用现有 Repository 接入 Mock 数据。导图 SHALL 两行两列展示并删除记录下方灰色说明；公司任务完整列表 SHALL 只展示当前用户接收的任务记录，无欢迎、搜索或筛选工具栏。月历 SHALL 移除下方当天列表并铺满可用高度，在长屏接近宽高约 1:2.5；普通屏 SHALL 优先保证月末可见，大字体 SHALL 按剩余高度显示完整月历，无需纵向滚动。周历 SHALL 填充剩余高度且每日预留两条记录。

#### Scenario: 导图和公司任务
- **WHEN** 用户打开导图并进入公司任务
- **THEN** 四块按既定顺序呈两行两列，预览无灰色日期说明，公司任务只展示本人接收的任务并可打开详情

#### Scenario: 日历查看全部
- **WHEN** 用户查看月历或周历并点击有多条记录的日期
- **THEN** 日历主体充分利用高度，月历下方无重复当天列表，日期弹层可访问当天全部记录

#### Scenario: 小屏及空数据
- **WHEN** 使用 320dp 或大字体，或 Mock 返回空记录
- **THEN** 不出现横向溢出，保留可访问日期、查看全部入口及明确空状态

### Requirement: 视图页新增入口与筛选收敛

视图页 SHALL 提供有权限用户使用的圆形新增入口，移除旧的任务/日志类型筛选，按日、周、月切换展示所选时间范围内的任务，不订阅或合并日志数据。

#### Scenario: 有权限用户新增任务
- **WHEN** 有任务派发资格的用户进入视图页并点击圆形新增入口
- **THEN** 打开任务创建表单，入口位于底部安全区上方且不遮挡记录

#### Scenario: 无权限用户访问视图页
- **WHEN** 无任务派发资格的用户进入视图页
- **THEN** 不显示圆形新增入口，直接调用创建接口仍返回权限拒绝

#### Scenario: 旧筛选入口
- **WHEN** 用户打开视图页
- **THEN** 页面不显示原任务/日志筛选控件，所有记录均为任务，页面不显示任务/日志类型提示或前缀

#### Scenario: 日志不可用及无任务
- **WHEN** 日志请求会失败或返回日志，所选日期没有任务
- **THEN** 日、周、月视图均不发起日志请求，不展示日志，任务空状态正常显示，任务请求失败时仍可重试

### Requirement: 月视图完整七列与紧凑记录

月视图 SHALL 在常规手机宽度内完整显示周一至周日七列，不依赖横向滚动。日期单元格高度 SHALL 根据剩余视口等分，完整月历无需上下滑动；记录在单元格内使用可读的短文本和颜色标签，不嵌套大型素材组件。

#### Scenario: 普通手机月视图
- **WHEN** 用户在 320dp 至 480dp 宽度的竖屏手机打开月视图
- **THEN** 七个星期标题和日期列同时可见，页面无横向滚动条，单元格内容不被截断到不可读

#### Scenario: 记录超过单元格容量
- **WHEN** 某日记录超过单元格可显示数量
- **THEN** 月视图最多显示三条记录且不显示额外记录，点击日期仍可进入完整列表

### Requirement: 月视图跨日胶囊和日期滚轮
月视图 SHALL 将日期数字显示在单元格左上角，每个日期最多显示三条记录；记录标题 SHALL 只显示原文前四个字符且不得溢出。跨日任务 SHALL 以连续矩形胶囊跨越涉及的日期格，仅开始日显示标题，其余日期只显示标签颜色。顶部日期控件 SHALL 打开年月日滚轮选择器，并提供取消和确定操作。

#### Scenario: 月历记录密度与跨日任务
- **WHEN** 一周内存在跨日任务或某日有超过三条记录
- **THEN** 跨日胶囊连续延伸且只在开始日显示前四字标题，每个日期格最多呈现三条记录

#### Scenario: 跨周及六周月份
- **WHEN** 跨日任务经过周末，或用户在小屏查看包含六周的月份
- **THEN** 色带在每周内部连续，跨周续段沿用同一轨道且不重复标题，最后一周在首屏完整可见，无需上下滑动

#### Scenario: 选择自定义日期
- **WHEN** 用户打开日期滚轮并取消，或选择日期后确定
- **THEN** 取消时当前日期不变，确定时共享选中日期更新到所选年月日

### Requirement: 全局柴犬素材和视觉一致性

移动端 SHALL 使用用户提供的卡通柴犬作为品牌装饰，不得继续显示旧小猪资源。柴犬 SHALL 不承担成功、错误、加载、审核或权限状态职责，不替代真实用户头像。标题字体、卡片、按钮、标签和状态 SHALL 使用同一套视觉令牌。优先级 P0，范围为 mobile 资源与页面装饰；业务契约不变。

#### Scenario: 页面和状态覆盖
- **WHEN** 用户访问导图、视图、日志、AI 地图、我的及其加载、空、错误和弹窗状态
- **THEN** 每个页面标题和区块标题左侧显示柴犬头像；状态仍由代码图标、文字和进度表达，任务管理入口及真实用户头像保留

#### Scenario: 素材加载失败
- **WHEN** 柴犬素材文件不存在或解码失败
- **THEN** 保留装饰占位空间并记录非敏感资源路径，不显示替代角色来掩盖缺图，不阻塞业务操作

#### Scenario: 资源子目录与裁切
- **WHEN** 生成 Flutter 资源包
- **THEN** avatars、poses、backgrounds 三个子目录 SHALL 显式声明；推荐素材清单记录实际内容及原图坐标，不把截断图片选作完整角色

#### Scenario: 月历装饰密度和窄屏
- **WHEN** 用户查看月历或切换日期
- **THEN** 星期栏七格右上角各显示不同表情的柴犬头像；今天日期格显示一张与星期头像不同的柴犬头像，其余日期只显示数字；可用宽度不足时优先保留可读日期和任务条带

#### Scenario: 导图卡片品牌装饰
- **WHEN** 用户查看导图页的四张入口卡片
- **THEN** 四个原入口图标分别由不同柴犬头像替换，四张卡片均在原卡片外框内叠加柴犬背景纹理，文字和记录仍可读

### Requirement: 简约通用组件视觉
移动端通用按钮、默认卡片、标签、筛选项、提示、弹窗、底部面板、空态、错误态和加载态 SHALL 不叠加角色状态图片。所有页面 SHALL 使用原有卡通纸张/插画背景，不得以纯色画布或柴犬背景替代。导图四卡 SHALL 保留原有卡片外框并在内部叠加柴犬背景纹理；其他柴犬背景只用于明确指定的装饰位置。通用控件 SHALL 使用清晰图标、细边框和克制阴影。

#### Scenario: 页面背景与指定外框保留卡通装饰
- **WHEN** 用户打开任一页面、导图四象限或日历视图
- **THEN** 全页面显示原卡通背景，导图四卡同时保留原卡片外框并显示柴犬纹理；日历保持七列、日期和任务条带，普通控件保持简约且交互语义可用
