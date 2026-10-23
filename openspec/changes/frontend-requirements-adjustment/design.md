# Design

## 2026-10-20 visual and mock-data correction

- Reuse the existing `TuantuanAssets.icons` PNG mapping for the seven “我的” rows; do not replace these domain icons with Shiba avatars or Material glyphs.
- Move month-view task bars down by a small fixed offset, constrained so the lowest supported bar stays above the date cell midpoint. Keep date labels and today decoration anchored at the top of the cell.
- Route interactive color through the existing warm primary theme roles. Replace explicit green/mint interactive treatments, including text actions and selected controls, with orange/warm colors. Preserve green only for semantic success indicators; retain independent department/category colors where they are data, not buttons.
- Keep the five existing roles in `UserRole`. Maintain at least 10 distinct demo accounts (the current seed has 20) across executive, product, engineering, marketing, customer-success, and administration departments and their teams. Use stable account data rather than `String.hashCode`; make organization tree, profiles, account switching, tasks, logs, reviews, and comments resolve to those same identities. Generate role-appropriate, non-identical task/log copy and realistic comment authors/timestamps.
- In each of the four dashboard tiles, render preview records in a top-aligned column with a filled warm-color circle at the start of each row. Keep a fixed row height/gap independent of how many records are present; do not use `Expanded` to distribute a sparse list across the tile.
- Add an opt-in `PageFrame` setting to omit its top title row on the five bottom-navigation root pages only. Keep child-page titles, back navigation, and meaningful action controls.
- No server, database, API, or authorization changes. Mock data remains explicitly demo-only and does not model production access control. The user asked not to run Flutter tests/analyze/build/device acceptance; OpenSpec strict validation is still required, while implementation tasks remain unchecked pending runtime evidence.

## 2026-10-20 member workspace and authentication visual refresh

- Replace the member identity banner's explicit pale-blue surface with a quiet warm-white surface, warm neutral border, and restrained apricot avatar accent. Keep member identity, read-only label, access lock, and return-to-self action unchanged.
- Redesign only login and registration presentation within the existing `FormPage`: branded title/mascot area, a two-option login/register segmented switch, grouped warm-white form surface, clear primary action, and compact registration disclosure. Preserve existing fields, validation, department loading/error retry, password visibility, auth routing, session lifecycle, employee-only registration and pending-confirmation behavior. Keep SMS-not-integrated disclosure accurate; add no recovery or verification flows without contracts.
- Reuse Material 3 and current app palette/components; no new package, theme-wide change, auth API, database, permission, or data-flow change. Narrow phone layout and accessible tap targets/text scaling are design targets; user-requested Flutter runtime verification remains deferred and tasks stay unchecked.

## 2026-10-20 authentication composition refinement

- Follow the supplied reference's hierarchy rather than its colors: a graphic-led hero region, compact capability rail, then a foreground sign-in/registration panel with a clear mode switch and primary action. Remove the current three-line product/welcome headline. Use editorial serif typography with restrained orange emphasis instead of the bundled rounded cartoon display font for the short hero phrase; use the Shiba pose as the brand visual. Retain warm-white, apricot and paper illustration surfaces, with deliberate density and no invented account state.
- Use compact icon-led capability labels for existing task, diary and calendar functions, plus a concise company-account/privacy note. Keep them informational; they do not navigate to protected routes before authentication.
- Product research: Slack documents email and Apple/Google sign-in choices; Figma documents email/password, Google SSO and SAML options; Apple HIG recommends explaining the value of sign-in and minimizing requested data. These products' authentication methods are not copied because this app's current contract supports account/password and pending employee registration only. No social login, SMS verification, password recovery, or SSO affordance is added without a real service contract.
- Keep the same composition for login and registration, adapting copy and form height. Registration policy remains visible and readable; form content scrolls under the existing page scaffold and bottom submit action.

## 2026-10-19 柴犬品牌装饰（覆盖历史角色状态和图片外框要求）

- 采用用户已批准的简约 iOS 气质：延续原卡通纸张/插画页面背景、简洁分组表面、20dp 圆角、细中性边线、16dp 页边距、12dp 卡片间距；保留现有导航和 Material 交互。参考 Apple HIG Layout 的分组、留白和内容优先原则，不引入 Cupertino 重构或第三方 UI 依赖。
- 路线 A 为每张卡片/日期重复铺柴犬与图片外框，侵占信息空间且容易失真；路线 B 为代码表面加少量原比例 PNG（采用），沿用公共组件，只增加纯色画布可选参数，兼容既有调用且可按页面回滚。
- `pubspec.yaml` 分别声明 avatars/poses/backgrounds；父目录仅用于清单。原始三张图不改动，脚本修正头像 4/8、动作 1/2/5/6 的跨格裁切；清单登记最终原图坐标、推荐用途与原图已截断限制。背景图已有 Alpha，局部 contain 放置，避免重复衰减后不可见。
- 所有页面与区块标题左侧放置柴犬头像。导图四卡分别用不同柴犬头像替换圆形入口图标，并在原卡片外框内叠加柴犬背景纹理。月历星期栏七格右上角使用不同表情头像，今天格使用与之不同的头像，普通日期不放头像。所有页面沿用原卡通背景，不以纯色画布或淡化柴犬素材铺满页面。
- 装饰 IgnorePointer/ExcludeSemantics，不裁耳朵、不映射身份/权限/成功/失败/加载。缺图保留布局，开发日志记录路径，不将爪印伪装为成功加载。权限/失败/加载由代码图标、文本与进度表达。
- 边界：仅 mobile 素材、pubspec、共享视觉组件、上述页面和相关文档。无数据、API、审核、时间窗口、事务、幂等或服务端变更，无新外部服务。现有混合改动保留，不提交/推送。假设沿用原图与现有导航；装饰位置为可逆视觉选择。
- 验收：规划执行 OpenSpec strict；静态追踪真实路由、资源目录和用途，Pillow 联系表复核裁切；最终仅差异审阅。用户要求不再测试，因此 Flutter analyze/test/build、APK 实际资源、320dp/大字/设备截图、无障碍运行与真实后端均不执行，相关 tasks 保持未勾选。可维护性目标为统一资源路径/用途与可重复裁切；无障碍目标为装饰不增加语义和点击阻挡，运行验收仍待后续授权。

## 2026-10-19 approved mobile control refresh

Use shared Flutter primitives in `mobile/lib/shared/premium_pickers.dart`: a rounded bottom surface, a painted month grid, a wheel time picker, colored tag capsules, and rounded option rows. Migrate the dispatch form and task-management filters to these controls. Task filters are limited to tag, participant, and an explicitly selected local calendar date; remove status and urgency controls and remove urgency from task creation/display. Keep repository calls and MockRepository as the only data boundary.

Use an explicit `draftSource=diary` route parameter only for the existing “continue local draft” action. The plus button opens a blank `log-edit` route with no draft parameter; `FormPage` restores local state only when the parameter is present. Submission retains the repository's uniqueness checks and existing 24-hour edit semantics. Public comments become one shared lightly tinted feed with compact author/time/body rows and inline reply attribution, keeping the existing posting command and error handling.

Acceptance is based on the affected widget/mock workflow tests, analyzer, debug Mock APK, OpenSpec strict validation, and `git diff --check`. No backend, database, API, or permission changes are included.

## 2026-10-18 视图追加批次

用户确认视图只显示任务。优先级 P0；范围为日/周/月、日期弹层、Mock 范围查询和定向测试；日志页及服务端接口不在本批次修改范围。删除 CalendarContent 的日志 provider 订阅和类型分支，仅通过现有 Repository 查询任务。加载、失败、空状态沿用任务请求状态，点击记录进入任务详情。

跨日任务采用全月区间轨道分配、每周绘制单个连续矩形条带；相比逐日排序绘制，可避免同一任务在相邻日跳行或断开。跨周复用同一轨道，续段不重复标题；起始格只显示标题前四个字符，限制在该格内。每天最多三个轨道，超过容量的记录不画在网格上，日期弹层仍列出全部任务。月查询包含首尾完整周，Mock 按起止范围重叠取任务。

月历按日期控件、底栏及新增按钮以外的剩余高度均分周行，替代最小行高及纵向滚动回退。默认假设普通手机竖屏；320×640、390×844、480×960、1.5 倍字体和六周月份用几何断言及截图验证。日期位于左上角，滚轮取消不改日期、确认才更新。其他验收包含：三视图无日志请求与类型前缀、日志失败不影响任务视图、第四条隐藏且日期弹层可访问、跨月/跨周轨道连续与标签颜色一致。无新权限、数据模型或公共接口变更，真实后端日期范围能力另行联调。

## 2026-10-17 九张新批注的批准批次

本轮优先执行用户最新文字与截图：Flutter 先接现有 MockRepository，后续通过 Repository 替换真实接口。对比页面内硬编码 Mock 和 repository Mock 两条路线，选择后者：沿用状态/分页/失败处理，页面不依赖数据来源，回滚仅涉及本批次 Flutter 文件。本批次不实施原设计的后端优先路线；数据库、Web、真实 HTTP 契约保持后续任务。

允许修改 dashboard/calendar/common 页面、路由、Mock repository、共享日志窗口模型、定向测试和本批次说明。导图恢复公司重点/公司任务/个人重点/个人日志两行两列，删除预览灰色说明；公司任务完整列表只显示本人接收记录并取消全部工具栏。独立任务管理查看本人及授权下属全部任务，仍提供管理用途的字段筛选与视图切换。月历移除下方当天列表，优先铺满可用高度，长屏接近批注的宽高约 1:2.5；避免在普通屏机械固定比例导致月末被截掉，大字体与普通字号均按剩余高度显示完整月历，无需纵向滚动。周历填满剩余高度，每日至少预留两条，底部留出加号空间。下属日志按最新图 5 展示部门日志时间线（覆盖旧图 13 的成员列表解释），同时显示作者姓名头像；部门与日期控件同排同风格。日志列表使用右下加号，草稿及提交后 24h 内点击直接编辑，超时进入详情，每行箭头始终可进入详情；详情底部提交/修改/锁定状态及公开评论回复。保留人员详情能力，仅删除两个重复的人员索引页及入口。

日志时间规则保持首次提交成功时间起算，修改不重置窗口，恰好 24 小时锁定；MockRepository 模拟服务端时钟并在写入时复核。客户端用统一窗口模型展示并定时刷新，真实模式最终以服务端裁决为准，不宣称本地过滤是权限边界。Mock 人员通过 managerId 表达上下级，不把全公司人员默认当下属。正常、空/失败、员工越界、空评论、回复、24h 内/边界/超时、320/360/480dp 和大字体作为本批次验收。

## Context

本变更依据 `D:\念\Download files\week5-前端设计需求调整.docx` 及其中 15 张截图标注，目标是让 Android 前端与甲方视觉稿、当前产品基线和真实后端契约一致。现有 Flutter 页面仍保留旧的首页加号、日期行、任务/日志筛选、分组/进度备注/主负责人/协作人字段、周报月报入口、版本历史和小猪资源；后端也尚未提供标签、任务开始时间、多人参与人、任务评论、删除审核、24 小时窗口及 Web 管理员门禁的完整契约。

当前分支为 `HCJ`，工作区已有用户拉取后的 README、docs、删除和诊断文件改动，本变更只新增规划文档，不触碰这些改动和业务代码。产品导航保持“导图、视图、日志、AI 地图、我的”，默认导图；所有数据范围、审核、版本和 AI 权限继续由服务端决定。

## Goals / Non-Goals

**Goals:**

- 按截图逐项调整首页、视图、月视图、任务、日志、评论、人员和消息的可见行为。
- 统一接入重新制作的卡通小柴犬、圆润加粗标题字体、标签颜色、卡片和状态素材，并覆盖加载、空、错误和弹窗状态。
- 建立前后端一致的 `startAt`、`deadline`、`participantIds`、`tagId`、`tagColor`、`submittedAt`、`editableUntil`、`canEdit` 和评论回复契约。
- 任务记录列表与详情参考用户提供的飞书移动端多维表截图：列表采用字段摘要卡片，点击整张卡片进入记录详情；详情采用顶部操作栏、标题、字段行和底部评论入口。
- 保留服务端审核、并发控制和审计能力；移动端隐藏版本历史和已取消的旧入口。
- 通过真实后端和 Android/Web 验收证明“登录—权限—任务—日报—评论—通知”主链路。

**Non-Goals:**

- 本变更不实现 AI 地图算法、DeepSeek 服务或新的离线同步协议。
- 本阶段不提供任务转派；现有转派/改期接口是否后续废弃由独立变更处理，移动端先隐藏入口。
- 人员页面第一版只读，不做编辑、拖拽、批量操作或组织结构维护。
- 团队周报属于外部验收文档，不恢复为产品页面功能。
- 日/周/月切换本身不属于本次改动；仅调整月视图内部布局和记录呈现。
- 不修改已发布 V1–V13 Flyway 迁移，不引入新数据库或消息中间件。

## Decisions

### 1. 需求冻结与截图映射

截图编号按 Word 内嵌图片出现顺序记录；实现时以截图标注为视觉优先级，以 `方案.md` 和本设计中的权限/数据规则为行为优先级。

| 编号 | 截图关注点 | 目标行为 | 规格/模块 | 优先级 |
|---|---|---|---|---|
| 1 | 首页右下新增加号 | 导图移除，加号仅在视图页按权限显示 | dashboard / Flutter | P0 |
| 2 | 首页日期与时间入口 | 删除日期行和底部时间视图入口，首屏展示更多内容 | dashboard / Flutter | P0 |
| 3 | 首页顶部 | 仅保留编辑入口，保持导航和返回行为 | dashboard / Flutter | P1 |
| 4 | 全局旧小猪 | 全页面替换为重新制作的卡通小柴犬 | assets / Flutter+Web | P0 |
| 5 | 视图顶部操作 | 增加圆形加号，移除任务/日志旧筛选 | view / Flutter | P0 |
| 6 | 视图记录数量 | 演示数据每天至少 10 条；真实不足不伪造 | view / data | P1 |
| 7 | 记录标签 | 使用创建时的预设标签颜色和分类 | tags / contract | P0 |
| 8 | 人员展示 | “我的”下独立页面，组织范围由服务端校验 | personnel / Flutter+server | P0 |
| 9 | 转派控件 | 本阶段移动端隐藏转派任务 | task detail / Flutter | P0 |
| 10 | 完成情况字段 | 追加到原任务说明，删除独立进度备注 | task form / contract | P0 |
| 11 | 任务写操作 | 新增、修改、删除均进入审核；删除复用审核链 | review / server | P0 |
| 12 | 截止时间样式 | 支持日期、小时、分钟，输入错误字段级提示 | task form / contract | P0 |
| 13 | 开始时间 | 新增开始时间并校验不晚于截止时间 | task form / contract | P0 |
| 14 | 人员字段 | 删除协作人和主负责人，改为参与人集合 | task form / contract | P0 |
| 15 | 标签模型 | 任务和日志共用一个标签，支持分类和预设颜色 | tags / server | P0 |
| 16 | 标签权限 | 只有创始人可编辑，其他用户只能选择 | tags / authorization | P0 |
| 17 | 公开评论 | 任务和日志支持作者、头像、时间、回复；不可编辑删除 | comments / Flutter+server | P0 |
| 18 | 版本展示 | 移动端取消任务版本和历史界面；任务后端保留版本/审核/审计，日报不使用版本控制 | detail / server | P0 |
| 19 | 日志类型 | 移除周报、月报，只保留日报 | logs / Flutter | P0 |
| 20 | 日志时限 | 从提交成功 `submitted_at` 起 24 小时内可编辑，之后编辑和撤回均拒绝 | logs / server | P0 |
| 21 | 下属日志 | 部门分组、搜索、部门筛选、日期筛选；不底部重复平铺 | subordinate logs | P0 |
| 22 | 消息分类 | 删除日志分类，保留评论通知 | notifications | P0 |
| 23 | Web 门禁 | 仅管理员可用；普通用户拒绝，Android 不受影响 | web / server | P0 |
| 24 | 团队周报 | 不作为产品页面功能，保留外部验收文档 | docs / non-goal | P1 |

当前已验证项：月视图星期标题已经在真机上验证可完整显示周一至周日七列，因此不再作为本变更的实现任务；后续只做月视图单元格比例、短文本、颜色标签和选中状态的回归检查。

### 2. 技术路线比较

| 路线 | 说明 | 兼容性 | 迁移/测试成本 | 风险 | 结论 |
|---|---|---|---|---|---|
| A. Flutter 先做本地展示，后端延后 | 先用 Mock 补齐页面，再等待接口 | 表面兼容，真实字段易漂移 | 初期低，联调返工高 | 会把 Mock 误报为完成，权限和时间窗口无法证明 | 不采用 |
| B. 先冻结 REST/OpenAPI 与迁移，再做 Flutter 垂直切片 | 服务端先定义字段、错误和权限，Flutter 每个页面接真实接口 | 与现有 Spring Boot/OpenAPI/Flutter 匹配 | 中等，需同步迁移和契约测试 | 早期需要跨模块协作 | **推荐** |
| C. 引入独立 BFF 或新 GraphQL 层 | 为页面另建聚合接口 | 增加一套契约和部署 | 高，需新服务和运维 | 超出 MVP，权限边界重复实现 | 不采用 |

推荐路线 B：项目已有 Spring Boot 分层、Flyway、统一 OpenAPI 和 Flutter repository，先冻结契约能让截图设计、服务端权限和真实演示使用同一数据模型；新增能力可回滚到 V14+ 迁移，不需要引入新基础设施。

### 3. 前后端数据与状态边界

Flutter 表单只提交业务字段，服务端负责权限、时间、审核和并发判断：

| 数据 | 请求 | 响应/展示 | 规则 |
|---|---|---|---|
| 任务时间 | `startAt`, `deadline` | 本地时区展示，服务端 UTC 存储 | `startAt <= deadline`；日期、小时、分钟必需 |
| 参与人 | `participantIds[]` | 人员头像/姓名集合 | 去重、在职、同公司且在派发范围内；不保留主负责人 |
| 标签 | `tagId` | `tagName`, `tagCategory`, `tagColor` | 每条任务/日志最多一个有效标签；颜色以服务端为准 |
| 日志窗口 | 提交/直接修改请求 | `submittedAt`, `editableUntil`, `canEdit`, `serverNow` | `now < submittedAt + 24h` 时作者直接修改当前日报，不审核、不生成版本；达到边界后编辑与撤回拒绝 |
| 评论 | `targetType`, `targetId`, `content`, `parentCommentId?` | 作者、头像、时间、回复关系 | 创建后不可编辑/删除，读取服从组织范围 |
| 任务删除 | 任务标识、版本、幂等键 | 审核申请状态 | 复用 review 事件；通过后归档，不物理删除 |

兼容策略：旧 `group`、`progressNote`、`collaborators`、`owner_id` 不再由新 Flutter 发送；服务端在迁移期间保留读取兼容或转换层，待所有客户端切换且数据迁移验证完成后再由后续变更清理。数据库只新增 V14+，旧迁移不可修改。

### 4. 模块职责与文件边界

- **A / Flutter 页面与素材**：`dashboard_pages.dart`、`calendar_content.dart`、`form_page.dart`、`detail_pages.dart`、`utility_pages.dart`、`app_router.dart`、主题和 `generated_assets.dart`；负责页面状态、可访问性和素材接入，不绕过 repository 直接调用网络。
- **B / 认证、组织、审核**：管理员 Web 门禁、标签权限、删除审核路由、人员范围查询；负责 V14+ 迁移和权限单测，不直接接管公共安全基类。
- **C / 任务和日报**：任务开始时间、参与人集合、任务说明追加、日报 24 小时直接修改窗口、下属日志筛选、评论领域规则；任务负责版本/审核，日报不负责版本/审核；负责任务/日志单元和真实 HTTP 集成测试。
- **D / 通知与分析**：评论通知、消息分类收敛、outbox/SSE 重连和演示数据边界；负责通知去重、失败重试和指标口径。
- **E / 公共契约与客户端接入**：OpenAPI、错误模型、Dio/repository、分页和时区适配，协调跨模块契约回归。

依赖方向固定为 Flutter → repository → REST/OpenAPI → Controller → Application/Domain → Infrastructure。Controller 不写 SQL 或业务规则；权限和数据范围在服务端执行。

### 5. 视觉和素材实施策略

- 重新制作一套卡通小柴犬 PNG/WebP 与必要的矢量图标，登记来源、版本、尺寸和许可；不使用百炼或外部热链。
- 以圆润加粗标题字体为 `AppTextStyles.title`，正文保持高对比和可读字重；字体文件随 APK 打包，缺失时回退系统圆润字体。
- 统一令牌：奶油白背景、薄荷绿、珊瑚橙、深色正文、标签颜色白名单、最大 8dp 卡片圆角、48dp 最小触控目标。
- 每个页面及加载、空、错误、审核中、无权限和评论弹窗状态都要走素材覆盖清单；月视图单元格只使用颜色标签和短文本，不嵌套柴犬卡片。

### 6. 审核、并发、失败与回滚

- 任务新增、修改、删除沿用候选版本/审核链；申请人不得自审，驳回必须填写原因。已提交日报在 24 小时内由作者直接修改当前内容，不创建候选版本、不进入审核；超过窗口后编辑和撤回均拒绝。
- 删除采用逻辑归档状态，保留任务、评论、通知和审计关联；若 V14 迁移失败，停止发布并保留旧客户端/旧字段读取路径。
- 所有写接口支持幂等键；版本冲突返回统一错误码和 traceId，Flutter 显示可重试但不覆盖他人内容。
- 标签、人员和下属日志查询先做公司与组织范围过滤，再执行搜索/排序/分页；前端隐藏控件不作为安全边界。
- 评论通知使用事务 outbox；SSE 断线按序号重放，失败时消息中心仍可刷新列表。

### 7. 验收矩阵

| 验收层 | 证据 | 必须覆盖 |
|---|---|---|
| 规格 | `openspec.cmd validate --all --strict` | 24 项需求、WHEN/THEN、任务未提前勾选 |
| 契约 | SpringDoc、`docs/openapi.json`、`docs/backend-interface.md` diff | 字段、权限、错误、分页、幂等、时区 |
| 后端 | `scripts/test-backend.ps1` 或 `-DockerMaven` | 任务/日志/标签/评论/审核/权限/24h 正常与异常 |
| Flutter | 定向 widget/集成检查和 Android APK | 五栏导航、素材覆盖、月视图七列、无横向滚动、大字体 |
| 真实 HTTP | PostgreSQL + Redis 环境记录 | 登录→权限→任务审核→参与人→日报→评论→通知 |
| Web | 管理员与普通用户各一条真实请求 | 管理员通过、普通用户拒绝、Android 不受影响 |
| 非功能 | 设备截图、无障碍和性能记录 | 48dp 触控、对比度/字号、列表和 SSE 重连表现 |

## Risks / Trade-offs

- 任务从单负责人迁移到参与人集合可能影响旧数据和统计口径；采用读取兼容与 V14+ 转换，迁移报告必须记录无法映射的异常记录。
- 24 小时窗口由服务端时间判定，客户端离线修改需要在恢复联网时显示窗口状态或关闭错误；不能用本地时间绕过限制。日报不提供版本回滚能力。
- 评论公开范围扩大了任务与日志的可见交互面，必须在 Controller 和查询层双重校验组织范围，不能只依赖页面入口。
- Web 当前页面能力与管理员工作台存在差距；本变更先落实后端门禁和前端拒绝状态，管理员工作台的完整审计功能另行验收。
- 新柴犬素材和字体若未及时产出会阻塞 UI 验收；在素材交付前只能使用登记过的占位资源，不能把旧小猪当作最终结果。
- 真实后端、Android 设备、PostgreSQL/Redis 和 SSE 环境任一不可用时，相关 task 保持未完成并记录证据，不以 Mock、编译或静态检查替代。

## Assumptions

- 人员页面第一版字段为姓名/头像、部门、参与任务数、今日或本周日志状态、任务完成/延期状态，并支持进入只读个人详情。
- 标签分类首版支持公司、部门、个人三类，具体可见范围始终由服务端授权决定。
- 完成情况追加到任务正文时采用带时间和操作者的追加段落，不覆盖原始说明。
- 任务删除通过审核后转为归档/不可用；是否提供恢复入口不属于本次范围。
- Web“仅管理员”覆盖 Flutter Web 和独立 Web 入口；若产品最终只限制独立工作台，需要在实现前更新规格。
- 评论回复使用 `parentCommentId`，评论不可编辑或删除。

以上假设均可通过接口或页面调整，不改变本变更的权限、迁移和验收边界。

## Open Questions

无阻塞性问题。Issue 编号、Sprint 编号、柴犬素材最终文件名和人员表格的非核心列在实现前补录，不改变本设计的行为契约。
