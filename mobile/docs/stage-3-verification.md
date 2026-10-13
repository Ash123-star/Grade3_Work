# 阶段 3 设计与 Flutter 验证记录

文件整理说明（2026-10-13）：命令与结果记录保留；历史原始过程日志已清理，名称仅用于追溯当时执行记录。后续日志统一放`.diagnostics/`，实际截图保留。详见[文档索引](README.md)。本次整理没有重新执行功能验收或改变既有结论。

## 2026-10-13 原关系图层级补齐（OpenSpec 2.26）

原5.4要求目标/依赖层级、来源和行动阅读，旧正式地图只是首目标加平铺卡片。本批按服务端真实有向边，通过强连通分组和无环层级计算位置，目标在同层居中、未关联节点明确说明、真实循环标识；箭头从卡片边界连接，100节点深层画布不再5000px截断。节点类型文字/颜色图例、来源数量、匹配的过滤节点/关系与列表、无结果清除入口、节点原作业真实来源与共享依据行动阅读已接；查看不生成任务，不猜连线或新增行动节点协议。

10项新增图布局/HTTP/UI/渲染测试覆盖分支合并/同层目标/循环自环/100节点/空与缺端点/筛选无结果/真实建议路由无写入/重复无效节点/旧会话与大字号列表末项。当前整批分析exit0、全量Mock **211项exit0**，正式16文件HTTP/安全状态 **181项exit0**；日志graph-final-analyze/mock/http.log。本批无API/数据库/新依赖/APK。对应UI使用原SunnyPaperTokens浅橙/薄荷/蓝/紫；原八屏布局保持。

实际 [关系图360dp/1.5](evidence/stage3-rebuild/55-ai-hierarchy-large.png) 已查看：图例、可拖动画布、真实上下层箭头与列表替代入口可读，长画布需要拖动，卡片只承载短摘要，全文通过节点弹层与列表读取；累计55单页图。100节点完整列表及无限层级非溢出已有运行证据。真实服务/供应商/设备与远程仍未验收，产品3.6/3.5保持未完成。同期Android Studio两处依赖启动阻塞已另行修复，见windows-startup-repair-verification.md，不混为UI验收。

## 2026-10-13 日志阅读登记验收（OpenSpec 2.25）

按原5.3连续文档末尾、评语之前接入显式“记录已读”。POST `/logs/{id}/read`只发送空对象，精确编码ID且严格要求`ok == true`；GET详情/历史与重建不写入。Mock也改为显式登记，正文与版本保持不变。只有已提交日志提供操作，忙碌和成功防重复；失败保留正文供重试，401/403清除整份受保护正文与评语，账号/令牌变化或离页忽略迟到结果。展示实际submitted_at上海时间；历史缺阅读人员字段说明清单不可用，不伪称无人阅读。

统一验收：分析exit0；全量Mock **201项exit0**；正式模式15个HTTP/安全存储契约文件 **171项exit0**，包含本批13项正常/异常/UI/实际截图测试。命令采用`dart.exe flutter_tools.snapshot --no-version-check analyze --no-pub`、`test --no-pub --dart-define=USE_MOCK=true --reporter expanded`，正式模式将define设false并传全部15文件；日志receipt-final-analyze/mock/http.log（本地忽略）。首轮规范提示与大字号测试懒构建定位问题集中修复后完成上述最终验收，未构建APK。

实际Flutter [日志阅读失败恢复](evidence/stage3-rebuild/54-diary-reading-recovery-large.png) 已查看：360×800、1.5字号，暖白连续文档末尾/次操作/失败说明/评语与固定修订按钮可达，无溢出；累计54单页图。非功能证据覆盖会话与权限隔离、失败可靠性及大字号可读性。正式服务没有阅读人员清单GET，登记确认只证明本次POST；真实服务器/数据库/设备与远程交付继续3.6/3.5未完成，本批不代表产品整体完成。

## 2026-10-13 日志多任务关联补齐（OpenSpec 2.24）

原设计5.3的连续文档关联区和现有LogContent.taskIds要求保留多个关联。审查确认旧Repository只取首项，表单单选，修订可能删掉其余ID。本批通过DiaryTaskLinks无损编解码、浅蓝可移除胶囊、独立授权搜索多选弹层和每项阅读入口修复；沿用原纸张分节和固定操作，不更换页面方案，不修改后端/API/迁移/依赖。

服务端数组全部载入，旧单ID草稿兼容，多ID存入现有加密字符串字段；键/账号/日期/原版本不变。搜索读全授权分页，第31项可选择，筛选不改已选，确认才更新正文，取消不改；去重保留顺序。暂不可查看的关联保留原ID直到显式移除，加载/后页403隐藏受保护标题且不改关联，阅读只提供实际可见任务链接。账号或token变更清理旧弹层内容且阻断旧结果。历史只读正文与草稿对照也保留全部关联。无效关联格式给明确错误，不默默变成空数组。

规划strict最初发现任务分组错误，已修复并通过15/15后才实施。集中验收发现6条分析问题、两个TextButton.icon测试定位问题，集中修正；截图最初未用真实异步区和根RepaintBoundary，已检查活进程后停止该测试，修正捕获并取得明确退出码，没有将旧截图算合格。真实视觉审查补齐浅蓝胶囊及键盘避让：弹层正文使用可滚动slivers，固定确认/取消在键盘上方。最终9项新增测试覆盖codec/数组GET与draft/revision版本/完整31条搜索/筛选保留/403/两个会话边界/取消确认移除/实际加密恢复及表单修订POST/多条阅读路径/未授权不导航/窄屏大字键盘与截图。

统一验收：Mock全量188项exit0；正式HTTP契约12文件135项及附件/管理补充2文件23项exit0，合计14文件158项。最后浅蓝样式补齐后受影响9项formal回归exit0，最终分析No issues found/exit0。不声称样式后重新跑过全量。Windows / Flutter3.38.7 / Dart3.10.7。测试均由 `D:\flutter\bin\cache\dart-sdk\bin\dart.exe D:\flutter\bin\cache\flutter_tools.snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=true/false --reporter expanded` 执行；正式集合为 `*_contract_test.dart`、`ai_http_workflow_test.dart`、`secure_local_state_test.dart`，另补 `attachment_assignment_http_test.dart`、`management_analytics_http_test.dart`。分析使用相同snapshot `analyze --no-pub`。日志links-final-mock/http/http-supplement/visual/analyze.log（本地忽略）；保留失败links-batch/repair记录不替代最终成功。未构建APK。

新增实际Flutter [多任务选择](evidence/stage3-rebuild/53-diary-task-picker-large.png) 为360×800/1.5字号正式HTTP适配渲染，已查看核对；原核心编辑截图06已由全量重新生成，连续纸张布局保留。非功能：加密草稿无损/会话权限隔离、键盘主操作可达/1.5字号与31条搜索。累计53张单页证据。真实服务器授权与数据库关系、Android密钥/原生存储、设备TalkBack、远程Issue/PR及其它产品接口缺口仍为3.6/3.5，不归档或宣称全部完成。

## 2026-10-13 实时消息与上下文完整读取（OpenSpec 2.23）

沿用阶段2主题、阶段3第6.4节收件箱和两张原八屏稿；本批没有重新定义页面方案，也没有修改后端、数据库、依赖或公共接口。正式模式通过已有 `/notifications/stream` 建立已确认前台会话的 SSE；只保留序列和连接状态，列表 GET 仍是权威数据。支持 UTF-8 分片、CRLF、多行 data、注释、帧大小限制、Last-Event-ID 重放、重复事件过滤和200ms刷新防抖。断线退避，连续五次错误停止并提供手动重连；401/403或格式错误停止。账号、令牌、权限、前后台及身份检查变化取消旧连接和计时器，Mock 不连接远程流。

组织树、公司/个人重点与审计详情统一严格完整分页：第31条可读，ownerId 保留；游标、数量、ID 不一致或后页403拒绝整批，不显示部分成功或伪造不存在。对应实现为 `notification_stream.dart`、`live_notifications.dart`、`session_lifecycle.dart`、Repository/context providers及消息/组织页面。

统一验收发现 SSE 与 AI 流测试替身混用、取消后的 Dio 计时器及旧分页 fixture 数量不符，集中修复：消息流独立返回、取消时清理监听、第一页按契约30条加后页1条；保留生产严格要求与负向断言。最终收回两个运行会话的明确退出码：Mock 全量179项、正式 HTTP 契约157项均exit0；AI与实时消息联合回归30项exit0。最终分析 No issues found；`openspec.cmd validate --all --strict` 15/15 exit0、`git diff --check` exit0。未构建APK。Windows / Flutter3.38.7 / Dart3.10.7；命令沿用 `D:\flutter\bin\cache\dart-sdk\bin\dart.exe D:\flutter\bin\cache\flutter_tools.snapshot --no-version-check`，分析/测试参数为 `analyze --no-pub`、`test --no-pub --dart-define=USE_MOCK=true/false --reporter expanded`；正式模式使用现有HTTP契约测试集合。日志 `live-final-analyze.log`、`live-final-mock.log`、`live-final-http.log`、`live-isolated-regression.log` 本地忽略，历史失败日志不作为最终成功证据。

新增 [消息重连恢复](evidence/stage3-rebuild/52-notification-recovery-large.png) 为实际Flutter360×800、1.5字号渲染，已查看：轻量连接说明、手动重连和列表刷新仍可达；累计52张单页证据。负向测试包含无效帧、超限、后页403、重复事件、五次失败、401、前后台/身份检查和旧账号迟到；非功能覆盖会话隐私隔离、断线可靠性及大字号可读性。HTTP适配器不证明真实SSE/outbox/数据库链或真机合格，整体3.6与远程交付3.5保持未完成。

### 原设计逐页对应核查

本次重新查看两张用户提供的PNG和实际八屏合集，核对结构与阅读顺序。下表是原方案的落实关系；动态日期、真实权限、内容长度和状态不要求与演示稿逐像素相同。

| 页面 | 原方案必须落实的结构 | Flutter实际证据 |
|---|---|---|
| 导图 | 小欢迎栏、紧凑2×2摘要、今日视图入口、派发FAB | [01-dashboard](evidence/stage3-rebuild/01-dashboard.png) |
| 视图 | 月标题、日周月、七列月历、选日议程 | [02-calendar](evidence/stage3-rebuild/02-calendar.png)，日周补充44/45 |
| 日志 | 下属固定入口、日报周报月报、日期行、草稿入口、底部写日志 | [03-logs](evidence/stage3-rebuild/03-logs.png) |
| AI地图 | 小紫色欢迎、编号建议及来源优先、次级内容、关系图入口 | [04-ai](evidence/stage3-rebuild/04-ai.png)，正式源补充34～39 |
| 我的 | 身份、消息/审批指标、工作/管理分组、设置帮助末行 | [05-profile](evidence/stage3-rebuild/05-profile.png) |
| 日志编辑 | 连续文档、关联任务、阻碍/计划/工时、保存时间、固定操作 | [06-editor](evidence/stage3-rebuild/06-editor.png) |
| 任务详情 | 胶囊、属性、说明、附件、真实事件时间线、固定主操作/更多 | [07-task](evidence/stage3-rebuild/07-task.png) |
| 审批详情 | 原因、旧生效/候选版本对比、审核链、独立底部决策 | [08-review](evidence/stage3-rebuild/08-review.png) |

主要构图已在本地渲染中核对；人物艺术外观仍需用户最终视觉评审，真实服务、Android Keystore/SQLite、原生文件对话框、TalkBack和远程Issue/PR仍未验收。支持反馈、任务退回补充、AI精细范围/确认原子版本契约仍未实现。HCJ混合历史改动保留，不提交或推送、不归档整体变更。

## 2026-10-13 原消息/列表与草稿同步补齐（OpenSpec2.22）

继续原阶段3第6.4/6.5节及阶段2纸张/橙色布局，重读两张批准设计板后实施；无替代主题、后端/数据库/依赖/公共接口改动。通用tasks/reviews/notifications/audit通过既有strict readCompleteList读全分页，保留既有查询/权限，停止旧会话后续遍历；总量、游标、不完整后页和403明确错误，刷新不显示旧受保护列表。第31条可搜索且未读/待审批计数含后页。任务仍无完成字段或状态筛选；消息/审计时间按上海展示。

单条已读与全部已读共用忙碌锁，真实成功才刷新。失败保留未读与可见错误，不导航；403清理正文并需显式权限复查。捕获账号/令牌，旧会话完成不刷新/不打开继任账号详情。只允许tasks/logs/reviews目标，审批走语义路由；未知/无目标说明不可用，已删除目标使用安全不存在页。

独立DiarySyncPage替换旧假检查。设置提供入口，日期选择独立于日历/报告/历史/编辑日期；读取本人当天完整列表/详情及加密本机草稿，修订按指定id/原版本键读取。非法日期/版本不读取，owner/day异常拒绝，网络错误与空服务器区别显示。检查/重新检查无命令/删除/覆盖，原稿加密readback仍相同。页内以纸张文档逐节显示本机/服务器正文及保存时间、原版本、当前生效或服务器草稿；底部继续编辑/重新检查。服务器已提交则进入修订并保留本机原serverVersion；只有对应账号/对象/同版本才能把原diary稿恢复至修订（已有revision稿优先），旧版本继续既有明确冲突重读流程；原diary不迁移/删除。

首次统一分析发现导入与mounted/braces lint，集中修正。新增测试的首次失败来自默认导图启动请求混入、未等待HTTP发出、provider刷新帧时序，以及用routeInformationProvider判断push页面（应检查实际FormPage参数）；修正测试启动/等待/实际编辑器断言，不削弱数据/权限断言。后续审查补齐已提交日志修订恢复及消息403清理，完成对应回归。

最终分析exit0，无问题。全量Mock171项exit0、正式HTTP十三文件144项exit0；之后仅追加两项403/单条旧会话负向测试，最终inbox_sync_contract_test全17项formal通过exit0（不声称全量已运行173/146）。这两项不改生产代码；最后分析仍exit0。Flutter测试包含实际编译，未构建APK。命令沿用D:\flutter\bin\cache\dart-sdk\bin\dart.exe flutter_tools.snapshot --no-version-check analyze/test --no-pub，测试--dart-define=USE_MOCK=true/false --reporter expanded。日志inbox-final-analyze.log/inbox-final-mock.log/inbox-final-http.log/inbox-final-negative.log（本地忽略）；首次失败保留inbox-sync-tests.log/inbox-sync-repair.log。

17项涵盖四资源31条/不完整分页、三类列表后页搜索、主页真实总数、刷新晚页403、消息去重/真实目标/全部已读失败重试/两种旧会话/command403清理复查/未知与删除目标、真实本机服务器对比/只读重查/原version编辑、修订与已提交日报恢复、非法路由零读取、空/网络/错误owner/day/403、独立选日与账户切换、生产路由窄屏渲染。非功能证据：隐私隔离（旧会话/失权清理）；可靠性和易用性（完整分页/保留草稿/固定动作/字号）。真实服务与设备权限链仍未证明。

新增实际Flutter [消息中心](evidence/stage3-rebuild/50-notifications-large.png)与[草稿同步](evidence/stage3-rebuild/51-diary-sync-large.png)，360×800/1.5字号，已查看核对；累计51单页图。通知保留分段/横滚类型/行式记录，同步长正文竖滚，固定底部动作可达。整体仍有产品接口/真实服务器数据库/设备/TalkBack/远程Issue与PR缺口，不归档或宣称整个产品完成。HCJ混合历史改动和gh缺失继续按AGENTS阻止自动提交推送。


## 2026-10-13 成员工作台与帮助（OpenSpec 2.21）

原设计第6.3/6.5节要求成员身份上下文、紧凑只读概览、分类完整记录及从下属日志携带业务日期。本批复用complete_list读取所有授权成员重点/日志/任务页；概览每类最多3条并提供实际可见总数/完整分类入口。本人公开时间线和下属日志只显示明确已提交日报，不把未知/草稿当正式记录。

成员日志日期独立按当前账号与成员保存；带date的路由严格验证YYYY-MM-DD，支持选择/清除，分类切换保留日期。下属日志每条提供成员工作台入口并携带当前筛选日；不改变日历、本人日志或周月报告日期。身份与当前分类整体异步门禁，后页403/失权撤下所有成员资料/记录，提供重新核对权限或安全返回；旧账号迟到请求不能发布或触发员工成员列表读取。权限仍由服务端裁定，本地过滤仅防御，不替代服务端验证。

帮助有无结果/清除搜索，正式模式说明反馈未接入且不导航至伪提交/列表；演示保留单独入口。指南保留已有600ms本机自动保存事实，明确草稿不等于提交；退回补充、审核候选、AI重新接流/明确生成/人工确认按当前实际能力解释。未引入新接口、依赖、后端或数据库变更。

验收先发现成员日期函数引用和修复过程声明/导入顺序错误，定位后修复并完成测试编译。随后测试发现滚动ensureVisible后未等待/权限面板没有泛用“重试”按钮、账号切换不够早阻止工作台provider继续读取；分别补齐等待、明确权限复核和provider身份门禁，不削弱负向断言。新增测试最终Mock12项、正式13项通过，整体Mock156/正式HTTP十二文件129项exit0，最终分析exit0无问题。全路由360×640/412×915大字号/800×1000继续通过。OpenSpec严格15项与git diff --check最终确认见命令证据；不构建APK。

命令沿用D:\flutter\bin\cache\dart-sdk\bin\dart.exe执行flutter_tools.snapshot --no-version-check analyze/test --no-pub，测试参数--dart-define=USE_MOCK=true/false --reporter expanded。最终日志member-final-analyze.log、member-final-mock.log、member-final-http.log本地忽略；失败日志member-batch-mock.log/member-repair-tests.log保留用于复盘。

新增member_workspace_contract_test覆盖31条最后日志真实详情、正确分页scope、紧凑预览与真实总数、日期携带/选择/清除/分类/成员独立、下属日志真实导航、非法日期/分类零读取、后页403整页清理/恢复、空与拒绝区分、账号替换迟到保护、公开未知/草稿过滤、帮助零结果/清除/正式无假接口、实际router截图。非功能：隐私隔离（失权清理/账号旧结果阻断）、可靠性与易用性（完整分页/恢复/可读层级/1.5字号）。

新增实际Flutter [成员概览](evidence/stage3-rebuild/47-member-overview-large.png)、[成员日志日期](evidence/stage3-rebuild/48-member-logs-large.png)、[帮助](evidence/stage3-rebuild/49-help-large.png)，360×800/1.5字号，累计49单页图；生产router、真实HTTP形状测试数据，不用HTML稿冒充App。长页可滚动，横向分类可滑动；设备TalkBack/触屏及真实服务数据库仍未验收。支持反馈/任务退回/精细AI范围与版本确认、远程Issue/PR仍是原产品未完成项，本批不宣称整体产品完成。

## 2026-10-13 日历/报告完整读取与固定周上下文（OpenSpec 2.20）

实施依据仍为原阶段3第5.2/5.3节与阶段2字号；未另建替代视觉方案。日历、本人/下属日志历史与报告使用既有列表完整分页，保留search/owner/date/period；总量变化、重复cursor/ID、缺cursor、空的不完整后页和403明确失败，不用部分内容冒充完整。上海业务日期从UTC+08转换，覆盖跨年/闰月/午夜；无时区旧样例保留业务墙上时间。

报告只聚合正式日报，草稿单列数量，缺失的是已过去的日历日期（包含周末），不是考勤分数。日历/日志筛选/报告日期独立。周日期和未设时段区固定在小时滚动区上方；双横向控制器同步，日/周日期模式保存纵向与横向位置。真实时段保持高度和重叠分列，仅截止以点标记并提供详情操作，不编造时长。补齐正文15sp及按钮16sp/600。真实设备时区/触屏/TalkBack仍未验证。

集中验收先发现月历两位日期在360dp/1.5字体换行溢出，以及新增测试未订阅autoDispose读取而自行取消。修复月历日期显式14sp/动态高度和测试订阅，不关闭生产取消保护；另清理两条import提示和测试语义句柄。最后视觉核对还发现新增按钮TextStyle未继承Roboto，导致渲染证据方框字；显式补齐与应用一致的字体并重新全量编译测试/截图，编辑与审批中文按钮已查看确认正常。实际截图改走生产router，加载中文及Material图标，并显式点击月报，避免孤立组件/错误周期截图。

最终分析exit0；全量Mock144通过exit0；正式HTTP十一文件116通过exit0；截图周期修正后新增12项formal复验exit0。测试包含Flutter编译，未构建APK。命令使用D:\flutter\bin\cache\dart-sdk\bin\dart.exe执行flutter_tools.snapshot --no-version-check analyze --no-pub，以及test --no-pub --dart-define=USE_MOCK=true/false --reporter expanded。OpenSpec严格15项通过exit0，git diff --check exit0。日志calendar-final-analyze.log、calendar-final-full-mock.log、calendar-final-http.log、calendar-final-render.log（本地忽略）；首次失败保留calendar-batch-mock.log/分析与calendar-repair-tests.log。

新增12项calendar_report_contract_test覆盖31条分页/保留查询/重复cursor/缺cursor/空后页/重复记录/总量变化/403/停止读取/业务日期/日期独立/报告草稿/周固定上下文/双向滚动同步与切换恢复/真实路由渲染。非功能证据：可靠性（拒绝不完整和失权后页、恢复滚动）；易用性/可读性（窄屏1.5字体、语义、真实网格）。本地HTTP adapter不等于真实服务/数据库授权验证。

实际Flutter新图：[日视图](evidence/stage3-rebuild/44-calendar-day-large.png)、[周视图](evidence/stage3-rebuild/45-calendar-week-large.png)、[月报](evidence/stage3-rebuild/46-report-large.png)，360×800/1.5字号，累计46张单页证据。核心16屏由全量测试再次渲染；已与原两张设计板对照检查构图/文字层级。日/周长页可继续滚动，固定日期仅对小时网格滚动生效；未将整个页面外层滚动伪称固定。报告AI精确本人来源、支持反馈/任务退回、真实服务/设备与远程交付仍未完成，整体目标保持未完成。

## 2026-10-13 原阶段2设计系统补齐（OpenSpec2.19）

依据原阶段2第4–10节和原阶段3八屏，不新增主题提案。已重新读取两个用户PNG参考板并逐屏对照实际Flutter。保留专用页面布局，完成真正SunnyPaperTokens ThemeExtension（颜色/形状/动效copyWith/lerp）、紫色AI和薄荷Material3角色、浅橙深可可前景；所有原FilledButton调用方统一迁移SunnyPrimaryButton，仍以真实Material FilledButton承载语义/键盘/回调。按钮52dp/18dp/3dp下沿、100ms下移2dp、加载保留标签及固定槽位、禁用不触发/无下沿、紫焦点圈、减少动画即时切换。导航选中使用橙色图标/文字，顶部24dp圆角并尊重减少动画。输入框必要边界1.5dp、焦点橙2dp、错误红2dp。

原创橙橙六姿态已实际接入：welcome导图/认证，writing日志草稿卡/编辑，explainingAI/身份检查，success已确认本机保存与建议保存，empty无记录，retry网络恢复。权限/待确认/停用用中性锁图标；候选待审不庆祝。插画排除语义、没有循环动画，所有状态继续用文字和恢复入口表达；素材记录[sunny-companion-assets.md](sunny-companion-assets.md)。日历任务/日志筛选新增toggled语义。

新增8项 sunny_design_system_test，验证主题插值/导航橙色、按压下沿/键盘焦点与Enter、禁用无动作、加载标签/宽度/语义、减少动画、空/网络/权限差异、真实成功反馈、日历切换及实际三张组件状态图。原日志交互测试同时确认已加密保存后的success姿态及实际读取密文草稿。非功能：①可访问性/易用性——键盘、语义、至少48dp目标、减少动画和1.5字号；②可靠性/隐私——忙碌无重复动作、失败保留输入、既有账号/权限/加密存储/SSE取消回归。真机TalkBack仍未验收。

首次集中验收：分析exit0，Mock127通过/5失败；3项AI测试原pumpAndSettle不能等待新增持续进度及真实HTTP/SSE时钟，2项语义句柄未及时释放。集中修复测试等待为有界真实/测试时钟推进并保留来源/请求/成功断言，释放句柄；组件截图背景捕获修正。27项组件/AI复验exit0。截图审查再发现导航继承AI紫，修正为原规范橙色并新增断言，因此执行最终全量回归。

最终可复现命令（mobile，FLUTTER_ROOT=D:\flutter；D:\flutter\bin\cache\dart-sdk\bin\dart.exe执行D:\flutter\bin\cache\flutter_tools.snapshot --no-version-check）：

```text
analyze --no-pub
  exit0, No issues found; sunny-final-analyze.log
test --no-pub --dart-define=USE_MOCK=true --reporter expanded
  exit0, 132 passed; sunny-final-mock.log
test --no-pub --dart-define=USE_MOCK=false --reporter expanded test/registration_contract_test.dart test/supporting_http_contract_test.dart test/command_http_contract_test.dart test/read_http_contract_test.dart test/auth_state_contract_test.dart test/management_analytics_http_test.dart test/attachment_assignment_http_test.dart test/ai_http_workflow_test.dart test/secure_local_state_test.dart test/sunny_design_system_test.dart
  exit0, 104 passed; sunny-final-http.log
openspec.cmd validate --all --strict
  exit0, 15 passed
git diff --check
  exit0, existing stage2 LF/CRLF notice only
```

实际43张单页FlutterPNG（另4张合集图）：原16屏已刷新，正式模式渲染覆盖认证/组织/统计/头像/附件/AI/安全恢复。新增[六姿态/按钮](evidence/stage3-rebuild/41-sunny-component-states.png)、[1.5字号](evidence/stage3-rebuild/42-sunny-states-large-text.png)、[字段/状态](evidence/stage3-rebuild/43-sunny-field-and-state.png)为390×844；完整路由覆盖360×640/1.0、412×915/1.5、800×1000/1.0；正式AI覆盖360×800/1.5。八屏和辅助合集由实际PNG重新生成并查看。动态日期/样例、额外实际协作人和结果段可与画稿不同，信息结构一致，未用画稿冒充Flutter。

仅task2.19对应客户端批次完成。产品未整体完成：支持反馈/任务退回/精细AI范围与确认原子版本缺服务端契约；实际服务器/数据库/供应商、原生存储/文件对话框/设备无障碍未验证。按用户要求未构建APK。HCJ混合用户/历史改动不自动提交推送，远程Issue/PR未完成；不归档和不关闭整体目标。下文为历次记录。

## 2026-10-13 加密草稿与安全会话恢复客户端批次

独立OpenSpec flutter-secure-local-state：原生Drift/AES-GCM密文、精确旧稿迁移、确认服务器草稿版本重入、安全credential和启动auth/me阻断已接。最新分析exit0、全量Mock124/正式HTTP96、严格15和diffcheckexit0；新增启动恢复错误页360dp/1.5字号，累计40单页证据。完整实现/命令/失败修复/平台边界见[本地状态验收](secure-local-state-verification.md)。真实AndroidKeystore/原生hooks、TalkBack和服务器/设备仍待验收；帮助反馈/退回/AI范围及远程交付仍缺，不关闭整体目标。下文为历次批次记录，安全存储旧“未实现”描述已由本节替代，不能当作最新状态。

## 2026-10-13 正式AI客户端批次验收（OpenSpec 2.18）

按阶段3第5.4节优先事项→依据→来源→人工确认、连续正文编辑、独立关系图布局落实正式模式；不再用旧通用卡片导航或“服务待接入”占位替代已有接口。截图审查发现初版筛选/状态挤占首屏，已收进日期周期筛选弹窗并压缩完成态，360dp/1.5字号下三条建议成为主体。地图目标节点优先，使用语义颜色、方向箭头、缩放/过滤与同内容列表。没有新依赖、服务器或数据库修改，原Mock演示明确独立。

客户端连接现有作业创建/GET、SSE/刷新/重新接流、DELETE取消、失败重试新job、版本草稿PUT、人工任务confirm-task、地图/关系和用量。日期和周期选择不自动调用模型；来源专项解释风险/拆步骤/起草建议保持原作业区间。SSE处理跨块UTF8、CRLF、多行data/keepalive和150000字符帧边界（result包含输入与输出）；累计未完成JSON不当作完整建议，终止后GET最终结构。失败/503/429保留输入和上次结果；重新接流不产生新生成请求。文件传输、供应商密钥不进入AI客户端。

严格来源路径与ID匹配，只能跳内部任务/日志/本人重点并保留owner上下文；来源缺失禁确认。草稿PUT保留来源/节点/候选ownerId及实际version，409不覆盖编辑，重读须确认。任务确认使用独立完整表单、真实ACTIVE人员/协作人及附件ID，未来期限，显式确认后GET核对job版本及建议，再POST actionIndex/task/幂等键；相同载荷失败重试保持键，修改载荷换键。成功后只有查看任务动作，不重复派发。旧通用ai-draft正式入口引导回来源有效的job流程。

新增19项 `ai_http_workflow_test.dart`：嵌套模型/110来源边界与内部跳转、SSE帧及真实Uint8List、精确请求与无自动任务、400/403/409/503/429、生成后的最终GET、失败保留旧结果/显式重试、取消/账号切换、403清除、草稿冲突/确认重读、缺来源/员工拒绝、人工任务真实ID与幂等重试、建议变化禁POST、地图/搜索/用量、旧账号迟到读取、无新调用重新接流、实际地图关系/专项purpose、生产router来源直达、节点弹窗账号切换清空、六屏实际Flutter渲染。HTTP adapter模拟已有服务形状，不证明远端服务或模型有效。

集中验收发现Dio Uint8List流→UTF8转码的运行时类型错误，修复为显式List<int>流；定向复验通过。测试的未挂载长页控件/异步最终GET/持续loading不能pumpAndSettle分别修正，未删除功能断言。首次分析在测试编写结束前执行，违反批次节奏，已承认并纠正；后续围绕失败和截图修复才复验。

最新证据：分析exit0，无问题；全量Mock109项exit0；正式模式八文件HTTP81项exit0（最终结果及命令见本地final-ai-http.log）；OpenSpec严格14项及diffcheck exit0。全部Flutter测试包含编译，不构建APK。命令仍使用D:\flutter Dart执行flutter_tools.snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=true/false --reporter expanded；正式八文件为registration/supporting/command/read/auth/management/attachment/ai对应test文件。日志final-ai-analyze.log/final-ai-mock.log/final-ai-http.log本地忽略。

实际Flutter新增 [AI优先事项](evidence/stage3-rebuild/34-ai-priority.png)、[建议依据](evidence/stage3-rebuild/35-ai-sources.png)、[草稿编辑](evidence/stage3-rebuild/36-ai-draft.png)、[人工确认](evidence/stage3-rebuild/37-ai-confirm.png)、[工作关系图](evidence/stage3-rebuild/38-ai-map.png)、[实际用量](evidence/stage3-rebuild/39-ai-usage.png)，360×800/1.5字号，正式模式截图使用生产router和已有HTTP形状响应，已检查无溢出/裁切，长页滚动和固定操作可达。累计39张分页面证据；六图更新由最终HTTP验收生成。

非功能证据：①隐私与隔离——认证请求、来源白名单、失权清空、旧账号不接迟到结果、地图弹窗也清除；服务端组织/数据库范围仍需真实验收。②易用性与可靠性——1.5字号和窄屏、连续文档/固定按钮、失败保存与显式重读、相同任务载荷幂等重试、SSE断流重接不自动收费。真机TalkBack/前后台/原生选择与保存、DeepSeek真实输出/预算/取消以及数据库链路未验收。

现有契约限制：date/period没有owner/scope参数，正式页展示实际身份范围，不提供无效“个人/公司”开关；更精确筛选需要后端独立设计。confirm-task不支持version前提，客户端GET与POST之间仍有并发编辑竞态，不宣称原子保护。地图每次读关联job还原来源，最多100节点，job顺序读取可能较慢，未做设备性能测量；服务端只提供本人jobs单读，没有历史分页，新会话不知道历史job ID时不能伪造历史列表。

仍未完成：加密Drift草稿、安全持久凭证/恢复、帮助反馈/真实退回补充、必要服务端范围筛选及真实服务/设备/远程交付。OpenSpec3.6记录产品级未完成事项，不将客户端批次全部勾选视为产品完成。HCJ混合用户/历史改动、gh缺失，按AGENTS不自动混合提交推送，不归档，不关闭goal。下面为历次状态，AI最新实现以本节为准。

## 2026-10-13 附件、头像及派发人员批次最终验收（OpenSpec 2.17）

继续以阶段2阳光纸张/动漫橙和阶段3第5/6/7节为基线，新增上传行状态、头像候选预览、受保护下载独立页及分页人员弹窗，不改变已重建八屏的信息层级。没有修改服务器、数据库、依赖或公共接口。

- POST `/attachments` 发送真实 multipart 字节并校验返回ID/文件名/尺寸；每文件1字节至10MB，头像限定PNG/JPEG/WebP实际签名。选取取消不变更，失败保留内存字节供重试，待上传/失败时阻止派发；离开或换账号取消并清除旧内容，迟到响应不进入新账号。
- 派发保存实际附件ID、单负责人ID及去重协作人ID；人员搜索和分页使用已有 `/organization/people?dispatch=true`，不把待确认/停用成员作为候选。成果/意见反馈现有接口不支持附件关联，明确不可用，未进行孤立上传；成果反馈保留阻碍文本。
- 本人资料显示授权下载的头像字节，替换后以新附件ID、现有介绍和真实版本保存；409保持原有效头像和输入。图片解码失败回退为姓名头像，可重试读取。身份仍只读。
- 任务附件打开独立下载页，GET重新校验权限，保留完整字节并使用清理后的服务端文件名。系统保存返回位置后才报告成功，取消/写入失败不报告保存成功，403禁止继续操作。没有公共文件URL或持久字节缓存。

新增 `attachment_assignment_http_test.dart` 11项契约/界面测试，覆盖字节、尺寸、无ID、403/404、失败重试、上传中禁提交、账号切换取消、头像409、保存取消/异常、实际协作人去重、人员分页搜索和字号1.5。首次验收发现测试点击不可见、同名目标、按钮子类查找及异步捕获问题，集中修复，保留业务断言。旧资料测试改为断言新上传入口，并继续验证保留旧头像ID/version/介绍；未削弱只读身份约束。一次全量命令漏传USE_MOCK编译参数而失败，修正命令后得到下面明确结果。

最终命令（mobile目录，FLUTTER_ROOT=D:\flutter，以Dart执行flutter_tools.snapshot --no-version-check；不构建APK）：

```text
analyze --no-pub                                                   exit0, No issues found
test --no-pub --dart-define=USE_MOCK=true --reporter expanded         exit0, 90 tests passed
test --no-pub --dart-define=USE_MOCK=false --reporter expanded test/registration_contract_test.dart test/supporting_http_contract_test.dart test/command_http_contract_test.dart test/read_http_contract_test.dart test/auth_state_contract_test.dart test/management_analytics_http_test.dart test/attachment_assignment_http_test.dart
                                                                  exit0, 62 tests passed
openspec.cmd validate --all --strict                               exit0, 14 passed
git diff --check                                                  exit0, only LF/CRLF notice
```

本地忽略日志为unified-analyze.log、unified-mock.log、unified-http.log、attachment-test.log及根unified-openspec.log。共33张实际Flutter渲染证据，新增 [头像编辑](evidence/stage3-rebuild/31-avatar-edit.png)、[附件下载](evidence/stage3-rebuild/32-attachment.png)、[任务附件](evidence/stage3-rebuild/33-task-files.png) 均为390×844、字号1.5，已人工检查无裁切/溢出，固定主操作可达，使用HTTP形状响应而非原型截图。全量回归覆盖三种尺寸。

非功能：①隐私/隔离验证旧账号上传取消、403不保留文件、下载附带认证，真实服务范围仍待验证；②可用性验证字号1.5、失败恢复/重试、取消无假成功及固定操作。系统选择/保存对话框、头像在真实设备显示、TalkBack和服务器/数据库链路未联调。服务器没有附件DELETE接口，移除或离开后可能留下未关联上传，生命周期清理须后续服务端设计；客户端不伪造删除。多文件字节暂存在内存，单文件10MB不等于总内存有上限。

仍未完成：正式AI作业/流式、帮助反馈、产品规划中的加密Drift草稿、安全持久凭证，以及真实服务/设备和远程交付。HCJ工作区混合用户与历史改动，按AGENTS不自动提交推送；OpenSpec3.5未完成。不归档或将整体验收标为通过。下面为历次记录，最新附件状态以本节为准。

## 2026-10-13 组织管理与统计批次最终验收（OpenSpec 2.16）

本批继续落实已有阶段3第6.3/6.4/7节，使用原阳光纸张与动漫橙。组织层级、当前配置/候选修改、四指标概览和固定操作是原设计的信息结构，不以旧通用表单或主题换色替代。服务端、数据库、依赖与接口均未修改。

- 组织读取已有 `/organization` 的实际部门/团队和 `/organization/people` 的全部授权分页，保留空部门和团队，名称显示/ID提交分离；成员详情读取 `/profiles/{id}` 的资料、当前版本与权限。
- 新增专用 `management_page.dart`：部门/团队新建或修改、员工归属确认、角色/派发资格/公司复核资格、汇报关系、停用以及审核策略。先读有效配置，提交明确候选字段、实际版本和理由。创建组织用版本0；公司复核资格属于人员字段，策略只提交两个实际审核开关。当前上级未返回时明确标注，不假造旧值；独立审核前原配置保持。Mock候选也不立即修改有效成员。
- 409保留输入、禁重复提交过期版本，重新读取前说明会丢弃未提交修改，取消保持输入；403清除受保护配置和表单。被驳回的组织修改不会误进入公司发布表单。
- 审计从现有授权分页读取，支持类型、发生日期和操作者标识筛选；只读详情展示实际事件、时间、对象、理由、前后值。没有单条GET时从授权分页定位，不构造不存在的地址；缺失/拒绝安全反馈。
- 正式统计读取 `/analytics?date=...&period=...` 的单个汇总对象，展示派发、逾期、按期验收率、日报提交率和部门分布；保留实际分子/分母/定义、区间、更新时间及未读日志。零分母显示暂无，错误不回退Mock。当前服务不支持部门/人员统计过滤、指标明细或趋势，界面明确边界，不从部分记录重算。
- CSV使用当前相同日期/周期、选择的任务或日志类型，经 `/analytics/export` 返回原始UTF-8/BOM字节。既有file_picker 10.3.10的saveFile(bytes)会实际写入文件，收到成功保存路径才显示完成；取消及写入异常分别反馈。系统保存对话框的真机人工验证仍未执行，测试通过可注入保存适配器核对路径与精确字节。

Windows / Flutter3.38.7 / Dart3.10.7，执行目录mobile，FLUTTER_ROOT=D:/flutter。使用D:/flutter/bin/cache/dart-sdk/bin/dart.exe调用D:/flutter/bin/cache/flutter_tools.snapshot --no-version-check：

```text
analyze --no-pub                                                      exit0, No issues found
 test --no-pub --dart-define=USE_MOCK=true --reporter expanded           exit0, 79 tests passed
 test --no-pub --dart-define=USE_MOCK=false --reporter expanded test/command_http_contract_test.dart test/read_http_contract_test.dart test/auth_state_contract_test.dart test/supporting_http_contract_test.dart test/registration_contract_test.dart test/management_analytics_http_test.dart
                                                                       exit0, 51 tests passed
openspec.cmd validate --all --strict (仓库根目录)                         exit0, 14 passed
```

`management_analytics_http_test.dart`新增12项：5项Repository/Mock契约及7项界面/渲染，覆盖跨页成员、空组织、当前权限、三类候选载荷/版本/理由、非法输入零请求、不立即生效、汇总对象/精确CSV、跨页审计缺失/403、冲突保留及取消重读、成员待确认候选、真实策略开关、零分母/口径/失权、保存成功/取消/失败、组织与驳回导航和大字号。HTTP adapter模拟已有服务DTO；界面→Repository→HTTP适配器链已运行，但不证明真实服务器/数据库审核链通过。首轮集中修复组件导入/测试API用法及括号规范；后续定向修复测试滚动等待与icon按钮定位，无权限/冲突断言未削弱。

累计30张实际Flutter PNG。新增24部门团队、25归属、26角色、27策略、28导出、29审计、30正式统计；390×844与1.5字号，系统微软雅黑和SDK MaterialIcons，[管理统计合图](evidence/stage3-rebuild/management-contact-sheet.png)。核心16屏和认证7屏由全量再次渲染；合图更新并人工核对，原批准两张参考板仍为依据。首屏字体增长、输入区滚动、固定底部提交对应原第7节；不构建APK。

非功能证据：①权限/隐私——对象403清掉当前配置、旧输入，失权禁提交；原配置与候选分开、禁止自审仍有原回归。②可用性——409保留理由、重读可取消、CSV取消不假成功、三尺寸及1.5字号路由布局通过。真实服务器权限/事务、系统保存对话框、TalkBack及真机生命周期仍待验收。

剩余：正式AI/上传/支持反馈、加密草稿与安全持久会话、真实服务/数据库/设备联调及远程交付，见完成性审查。HCJ混合历史/用户改动，且gh缺失，按AGENTS不自动混合提交推送；OpenSpec3.5未勾选，不归档、不报告整个产品完成。下文为历次记录，其旧缺口由本节及2.15说明更新，不能当作最新实现状态。日志stage3-analyze.log、stage3-full-mock.log、stage3-http.log、stage3-management-test.log为本地忽略文件。


## 2026-10-13 认证状态批次最终验收（OpenSpec 2.15）

本批落实原设计第6.5节已有认证页面，保持阳光纸张/动漫橙与权限边界。不修改服务器、数据库或公共接口。

- Session从实际status、must_change_password、expiresAt构造，不把缺状态默认激活；待确认/首次改密/停用/到期阻断业务入口和请求，账号身份、申请部门名称和恢复动作留在状态页。
- 待确认通过GET auth/me刷新；网络失败保留申请状态并重试，只有ACTIVE且无改密要求进入导图。注册不伪造token，登录后再刷新确认。
- 明确SESSION_EXPIRED/受保护401清除旧token并跳转失效页；PASSWORD_CHANGE_REQUIRED/MEMBERSHIP_PENDING分别限制访问；普通对象403及INVALID_CREDENTIALS不撤销当前会话，错误密码保留表单。旧令牌请求和前台验证结果不能覆盖新账号。
- 密码成功须返回reloginRequired，清除旧会话并登录；退出先POST auth/logout，网络错误保留会话及重试，401视为会话已不可用。退出/失效保留按原账号隔离的草稿，受保护栈受路由约束。
- 前台恢复以auth/me验证，原页面保持挂载以保留输入，但隐藏内容/语义与操作。网络失败显示验证恢复页，不能绕过；到期计时采用真实expiresAt。令牌只在内存，未实现安全持久化恢复，进程重启要求登录；不将它称为完整会话恢复。

新文件core/state/session_lifecycle.dart处理到期/前台验证UI；providers.dart维护身份及旧令牌保护；repository.dart保留错误code、现有auth/me和auth命令；form_page.dart/utility_pages.dart接登录改密/申请刷新/退出。无新依赖或迁移。

`test/auth_state_contract_test.dart`10项包括2项模型/HTTP映射和8项页面/渲染：缺状态安全阻断、普通403与真实会话错误、待确认深链零业务读取及503后确认激活、强制改密深链/确认不一致/原密码401保留/成功重新登录、登录错误不误失效、服务端退出503重试且草稿保留、旧请求不能撤销新会话、expiresAt到期、前台验证失败/恢复/换账号竞态，以及360×720/1.5字号认证状态渲染。首次全量验收修复规范提示及旧设置页卸载前重建演示选择器问题，未放宽断言。

最终命令（同下方Dart snapshot方式，mobile目录，FLUTTER_ROOT=D:\flutter）：

```text
analyze --no-pub                                                           exit0, No issues found
 test --no-pub --dart-define=USE_MOCK=true --reporter expanded                  exit0, 67 tests passed
 test --no-pub --dart-define=USE_MOCK=false test/supporting_http_contract_test.dart test/command_http_contract_test.dart test/read_http_contract_test.dart test/auth_state_contract_test.dart --reporter expanded exit0, 37 tests passed
 test --no-pub --dart-define=USE_MOCK=true test/stage3_reference_render_test.dart --reporter expanded exit0, 1 render test passed
```

日志stage3-analyze.log/stage3-tests.log/stage3-http-tests.log/stage3-auth-tests.log/stage3-render.log为本地忽略文件。全量包含三尺寸/字号1.5和16屏Flutter渲染；另新增7张实际认证状态图，[合图](evidence/stage3-rebuild/stage3-auth-contact-sheet.png)：17登录、18待确认、19强制改密、20失效、21停用、22验证中、23验证失败恢复。字体系统微软雅黑、SDK MaterialIcons，未使用原型冒充渲染。人工检查认证屏主要信息和恢复动作，无业务底栏。HTTP adapter模拟已有服务DTO，不证明真实服务器和数据库撤销链；服务端停用返回SESSION_EXPIRED而非可辨识停用错误，客户端不得从401猜测停用原因。未构建APK。

非功能：隐私/授权验证待确认与强制改密零业务请求、失效禁读、旧会话结果隔离；可用性验证503可重试且改密输入/草稿保留，窄屏字号1.5无异常。真机TalkBack/应用前后台切换及系统截图仍未人工验收。整体缺口见完成性审查，远程混合工作区与gh缺失继续阻止提交推送；不归档、不报告整体完成。

## 2026-10-13 读取契约批次最终验收（OpenSpec 2.14）

该批仍沿用原阶段3第5/6/7节与批准参考板，没有替换设计方向，没有修改服务端、公共接口或数据库。

- 重点详情从已有授权分页定位ID；成员重点保留ownerId，页末/重复游标/缺失/403安全结束。
- 已提交日志读取独立versions/comments，历史正文不代用当前正文，评语显示实际文本/作者ID/时间。网络或5xx保留主文档并提供局部重试；401/403拒绝整个受保护读取；草稿不请求正式附属接口。
- 任务详情依据sequence排序的生命周期事件恢复操作；REVISED清除旧成果并回到待接收，转派/延期事件保留阶段，未知事件不猜主操作。附件/协作人尚无名称服务时明确显示ID。
- 通知映射is_read/recipient_id与已知对象目标，未知类型无臆造跳转。

`test/read_http_contract_test.dart`新增9项（5项适配、4项页面链路）：跨页/成员范围/缺失/403，独立历史正文和评语，局部503重试及403清除，事件乱序/REVISED/未知阶段，实际通知字段，以及负责人/派发者主操作。HTTP adapter模拟已有DTO；未启动真实服务/数据库。首次验收修正括号规范和测试函数顺序；页面测试另修正初始路由取证及等待Riverpod真实刷新，不削弱权限与未知事件断言。

最终集中证据（Windows，Flutter3.38.7/Dart3.10.7，mobile目录）：

```text
analyze --no-pub                                          exit0, No issues found
 test --no-pub --dart-define=USE_MOCK=true --reporter expanded exit0, 57 tests passed
 test --no-pub --dart-define=USE_MOCK=false test/supporting_http_contract_test.dart test/command_http_contract_test.dart test/read_http_contract_test.dart --reporter expanded exit0, 27 tests passed
```

执行前设置FLUTTER_ROOT=D:\flutter，使用D:\flutter\bin\cache\dart-sdk\bin\dart.exe运行D:\flutter\bin\cache\flutter_tools.snapshot --no-version-check，完整方式见下方。日志stage3-analyze.log、stage3-tests.log、stage3-http-tests.log和stage3-read-tests.log保留在本地忽略文件。全量检查包含16屏重新渲染及三尺寸/1.5字号验证；下方截图和合图为本批结果，人工检查主要信息顺序与固定操作。未构建APK。真实后端/认证细分/设备无障碍/远端交付仍未验证，详见完成性审查。

## 2026-10-13 重做批次统一验收（历次累计证据）

本次验收以 `stage-3-page-layout-and-interaction-design.md` 第 5、6、7 节和两张批准的 390dp 参考板为基线。16 张证据图（核心八屏及辅助八屏）均由 Flutter `RepaintBoundary.toImage` 生成，未使用 SVG/HTML 原型替代：

- [导图](evidence/stage3-rebuild/01-dashboard.png)、[视图](evidence/stage3-rebuild/02-calendar.png)、[日志](evidence/stage3-rebuild/03-logs.png)、[AI 地图](evidence/stage3-rebuild/04-ai.png)、[我的](evidence/stage3-rebuild/05-profile.png)
- [日志编辑](evidence/stage3-rebuild/06-editor.png)、[任务详情](evidence/stage3-rebuild/07-task.png)、[审批详情](evidence/stage3-rebuild/08-review.png)。辅助页面另见下方 09–16 矩阵。

[核心八屏合图](evidence/stage3-rebuild/stage3-rebuild-contact-sheet.png)、[辅助八屏合图](evidence/stage3-rebuild/stage3-supporting-contact-sheet.png)。Windows / Flutter 3.38.7 / Dart 3.10.7；截图尺寸 390×844，测试加载系统微软雅黑及 SDK Material Icons。详情/辅助截图从对应主页面 push 进入，验收/转派经任务详情、版本文档经日志与历史入口进入，保留返回按钮；不含 Android 系统状态栏。

| 页面 | 对照结果与有意差异 |
|---|---|
| 导图 | 四区位置、色彩、两条摘要、人物与今日视图对应。日期/保存时间来自当前状态，个人日志不伪造提交。业务标题可换行。 |
| 视图 | 月标题、周期、类型图例、七列日期和议程对应。10月12日只有一条真实 fixture 任务，因此不是原图的两条；今天轮廓与选日同时显示。 |
| 日志 | 草稿条/月分组/大日期行/底部 CTA 对应；不同业务版本号按实际记录显示。周月报采用源日报聚合，不伪造独立发布接口。 |
| AI | 首屏三条编号建议、来源、次级内容、关系图入口对应；团队长范围显示团队，不能套用公司范围。 |
| 我的 | 身份、真实指标、工作/管理行及设置帮助对应；字母头像为未接头像服务的明确边界，角色增加一行，指标来自数据。 |
| 日志编辑 | 连续纸张分节与底部双操作对应；正常态不显示参考板的失败框。失败态和键盘可达另由交互测试验证。工时保留实际输入控件。 |
| 任务 | 属性、正文、附件和时间线对应；fixture 实际存在协作人及成果，增加阅读区。单一主操作与更多菜单保持。 |
| 审批 | 原因、有效/候选上下叠放、独立链及固定双按钮对应；Mock 为三节点，真实模式仅显示实际 steps，缺人保持待配置。 |

补充第 6、7 节契约的证据：

| 辅助屏 | 实际 Flutter 截图 | 原设计对应与边界 |
|---|---|---|
| 验收 | [09](evidence/stage3-rebuild/09-acceptance.png) | 先阅读真实成果/阻碍/附件，再填写验收意见，底部固定提交。附件仅代表返回的记录，不代表上传/下载已接入。 |
| 转派 | [10](evidence/stage3-rebuild/10-transfer.png) | 当前有效版本、旧负责人/期限在上，候选负责人和原因在下。服务器候选审核映射仍需联调，不能由文案证明已生效。 |
| 本人主页 | [11](evidence/stage3-rebuild/11-profile-document.png) | 资料与只读组织身份、公开重点、按日期倒序的已提交日志；不混入草稿。 |
| 版本文档 | [12](evidence/stage3-rebuild/12-history-document.png) | 打开指定版本只读正文、版本信息与理由；此 fixture 只有当前 v1，缺失时间/理由明确标未返回。历史 v1 与当前 v2 的正文隔离及不存在 v99 由行为测试验证，不伪造截图。 |
| 组织 | [13](evidence/stage3-rebuild/13-organization.png) | 授权范围、搜索、实际人员归属的可展开部门/团队；完整组织树管理未接入。 |
| 设置 | [14](evidence/stage3-rebuild/14-settings.png) | 当前阅读字号、帮助/密码/隐私/许可和退出。角色、账号和场景选择只在演示模式。 |
| 帮助 | [15](evidence/stage3-rebuild/15-help.png) | 搜索指南、常见问题与反馈入口；生产反馈处理未接入。 |
| 日志阅读 | [16](evidence/stage3-rebuild/16-log-reader.png) | 正式业务日期/作者/版本、连续正文与关联/阻碍/计划、独立评语、历史入口、固定本人修订操作。 |

`test/stage3_supporting_ui_test.dart` 的四项测试覆盖：成果阅读后空验收意见拒绝及转派旧值；历史正文/理由、缺失版本与本人时间线排除草稿；本人备注新建/阅读与他人重点不泄漏；主操作超时后错误紧邻固定按钮、404 可安全返回且无提交动作。这里的 UI → Mock Repository → DemoStore 路径已运行；它不证明 HTTP/数据库链路。

截图测试最后仅调整取证导航并单独运行，明确 exit 0、1 passed；未因此反复运行无变化的生产代码检查。原产品批次全量 48 项通过（其中 18 项为既有 HTTP 适配契约测试），补充取证导航编译通过。两组合图均已重新生成并人工检查，不再沿用旧图。

辅助布局映射：`detail_pages.dart` 行式任务/消息/审核/审计及连续日志阅读；`form_page.dart` 三组派发、独立成果反馈、认证与关键变更表单；`member_workspace.dart` 上下文及分类；`organization_browser.dart` 从可见人员实际归属建立可展开分组；`demo_pages.dart` 周月源日报、统计口径、可缩放关系图/列表替代和帮助；`utility_pages.dart` 设置/系统状态。审核策略表单提供候选路由示意，明确实际审核链以服务端返回为准。

逐屏对照确认信息顺序和构图已经对应：导图为欢迎条、2×2 摘要和今日视图；视图为周期胶囊、七列月历和议程；日志为周期浏览、真实草稿和日期行；AI 地图为范围、编号建议、来源和关系图入口；我的为身份、指标和分组行；三个详情页分别为连续日志、属性/时间线、旧版/候选版对比。文案和数据采用 Mock/fixture 时保留演示标记，未声称与生产数据相同。

统一命令及结果：

```text
openspec.cmd validate --all --strict                         exit 0, 14 passed
dart.exe flutter_tools.snapshot --no-version-check analyze --no-pub  exit 0, No issues found
dart.exe flutter_tools.snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=true --reporter expanded  exit 0, 48 tests passed
dart.exe flutter_tools.snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=false test/supporting_http_contract_test.dart test/command_http_contract_test.dart --reporter expanded  exit 0, 18 tests passed
dart.exe flutter_tools.snapshot --no-version-check test --no-pub --dart-define=USE_MOCK=true test/stage3_reference_render_test.dart --reporter expanded  exit 0, 1 test passed
```

在 mobile 工作目录设置 `FLUTTER_ROOT=D:\flutter`，上文 dart.exe 完整路径为 `D:\flutter\bin\cache\dart-sdk\bin\dart.exe`，snapshot 为 `D:\flutter\bin\cache\flutter_tools.snapshot`。日志为 mobile/stage3-analyze.log、stage3-tests.log、stage3-render.log（本地忽略）。使用 snapshot 避开 Windows batch 无输出/版本网络检查；仅在收尾新改动或诊断失败时重新运行受影响检查。

布局测试覆盖 360×640、412×915（字体 1.5）和 800×1000，所有已注册路由滚动后无异常，含日/周/月直达和组织分组；行为测试覆盖日期独立、草稿保存/提交失败保留输入、工时非法输入、离线重试、自审禁止、驳回原因、任务主操作唯一、AI 草稿按账号隔离、版本过期禁止提交且明确重新读取。至少一条系统层 Mock 链路由编辑 UI 到 Repository/DemoStore 数据更新闭环；这不包含真实数据库验收。未执行 APK 构建，符合本轮明确约束。

非功能证据：①可读性/可用性——三种尺寸及 1.5 字号无布局异常，主操作保留于底部且键盘 inset 300 时仍可达；常规按钮与周期目标 48dp。七列月历格宽受手机宽度限制，小于48dp，格高≥48dp并提供完整议程入口，真机触控仍需评审。②隐私/权限——员工不能派发/查看下属、申请人不能自审、AI 行动和本机日报按账号隔离；服务端范围校验不由这些客户端/Mock 测试证明。

本轮仍需单独联调或人工验证的内容：真实后端注册/会话、真实附件上传、服务端 AI 作业/流式、真实统计导出、设备 TalkBack/键盘和减少动态效果、远程 Issue/PR。它们不被 Mock、分析通过或截图证据替代；UI 页面在真实服务未接入时明确显示待接入/空态，不回退为假成功。

接口交接核对：服务端 `DashboardController` 已有 GET/PUT `/private-notes`，PUT 使用 resource、objectId、text、version（新建 0），GET 返回本人记录的 resource/object_id/owner_id 与 UUID；仅支持 tasks 与 dashboard/company。客户端已在 Repository 层将复合展示键解析为 resource/objectId/account，读取时匹配服务端返回的 owner/resource/object_id，保存时发送 objectId/text/version；个人重点备注仍不在该服务器支持范围。`/me/profile` 姓名保持只读，介绍更新保留服务端返回的 avatarAttachmentId。10 项 HTTP 适配契约测试通过，但真实数据库、认证和组织范围仍需联调。日志版本和评语现已通过2.14独立GET读取，见上方最新验收。

### 原第6节 HTTP 适配补充验收（2026-10-13）

本批代码：`data/models/models.dart` 的备注目标键；`repository.dart` 的备注查询/写入及 profile 嵌套映射；`form_page.dart` 的本人键校验、真实版本、只读姓名和头像引用保留；个人重点在真实模式提供未接入提示，不能保存到不支持的资源。根产品方案 §6 只允许头像/介绍编辑，阶段3原文的“姓名可编辑”已纠正为只读。

`supporting_http_contract_test.dart` 覆盖4项映射测试和6项页面测试：UUID/资源/对象/账号不混用；新建0及更新实际version；非法/不支持目标不发请求；嵌套资料和头像引用；UI409输入保留；缺备注新建再打开；403禁提交；他人键在HTTP读取前拒绝；姓名只读且介绍更新使用version7；真实模式不支持目标禁提交。使用 Dio HTTP adapter 模拟已存在服务器响应结构，界面→HttpRepository→请求/响应映射均实际运行，未启动远端服务器和真实数据库。

首次统一验收发现测试读取错误组件属性和一个括号 lint；之后 HTTP 检查发现 `id` 被通用参数转换移除及未等待 PUT 导致409绕过错误转换。集中修复后 HTTP10/全量40/分析均exit0。修复没有削弱冲突、隐私或可编辑范围。相关日志：stage3-http-tests.log、stage3-tests.log、stage3-analyze.log（本地忽略）。

### 原第6节核心对象写入补充验收（OpenSpec 2.13）

客户端执行命令保留原始 id，只有任务候选 DTO 使用去掉 id 的字段转换。修改已有对象缺 id 本地拒绝；任务/日报/评语/审批/通知使用明确对象路径；私人及公司重点发送服务端允许的 id/title/text/version/排序等字段，不把展示受众和中文 UI 字段原样发给严格字段校验。归档沿用已加载重点的标题/正文/排序/置顶，未新建对象。所有异步写请求等待响应后再进入既有 Dio→ApiFailure 转换。

转派/延期读取实际授权任务，核对提供版本，保留负责人、期限、标题、内容、紧急度、备注、附件ID及协作人ID，只替换所申请字段，经已有 `/tasks/{id}/revisions` 提交完整候选和理由；不走立即生效的 events。现有服务端无退回补充事件，真实模式禁提交并提示未接入，不当作FEEDBACK。其它正常接收/反馈/验收/撤回/归档仍用已有 events。

日志新建或编辑已有草稿先 PUT draft，再以返回 ID/version提交。若保存已成功但submit失败，DiarySubmitFailure只保留确认的草稿ID/version，编辑器保留输入并用同一草稿重试；不包含正文日志，不以version0重复创建。已提交正文用request-review。

`command_http_contract_test.dart` 的8项包括：5类对象真实路径和允许载荷；缺ID/不支持事件零请求；转派/延期完整候选及当前对象不变；旧版本/无理由无修改；返回version9及已有草稿version10提交；重点归档/发布ID与允许字段；6类异步写409转类型；日志UI从503保留输入到再次写version9和submit10成功。`USE_MOCK=false` 两组HTTP适配测试18项通过，最后改动后的8项定向测试及全量48项均exit0，分析exit0；相关日志stage3-command-tests.log、stage3-http-tests.log、stage3-tests.log。

2.13时的读取审查项（已在2.14修复，保留审查经过）：`/logs/{id}/versions` 与 comments 在服务端代码已存在，客户端历史/评语仍仅依赖嵌入字段；公司/个人重点无单对象GET但客户端detail仍构造该路径；服务端 taskDto未返回phase，客户端主操作状态需由真实events恢复。另需核对通知is_read、当前账号会话状态/强制改密。以上属于剩余客户端接入，不应依靠Mock或本批写入测试声称完成。

风险：本机草稿仍使用未加密 SharedPreferences，不是规划中的加密 Drift；上传仅本地文件选择；真实任务“退回补充”及管理策略接口不能由现有通用 Command 猜测完成；真实私人备注已完成客户端 HTTP 映射测试；真实服务权限、数据库冲突和部署环境仍未联调；会话恢复/强制改密及停用跳转需要单独联调。组织分组只依据人员归属，未表示已实现服务端完整组织树管理。无接口或数据库迁移。回滚可按页面恢复组件，保留草稿键与版本语义。

假设：本轮周期报告为既有源日报聚合；截图核对层级/构图/交互，不要求动态业务文案与原型像素相同。两项均沿用已批准视觉批次边界。

远程交付：HCJ 工作区混有上一阶段代码、用户图片和未跟踪文件，未能可靠隔离；gh 未安装，没有远程 Issue 编号或 PR。遵守 AGENTS 混合改动停止自动推送的约束，不提交他人改动，OpenSpec 3.5 保持未勾选，不归档变更。

## 2026-10-12 历史记录（已由上方重做验收替代）

2026-10-12，Windows，Flutter 3.38.7 / Dart 3.10.7。用户要求完成批次后集中验收；编码中未反复执行完整分析。

## 本轮交付

- 页面需求矩阵、五主页/业务页布局契约、两份原创 SVG/PNG 设计板。
- 离线 HTML/CSS/JS 原型：五栏、日周月、编辑失败/重试、AI 来源、人工确认、成员分类、审批原因。JS 语法检查退出 0；浏览器逐项点击未验证。
- Flutter App 主题、圆润组件、原创静态工作伙伴；导图四象限、手机月历选日议程、周小时刻度、日志行式历史、表单纸张容器、AI 优先建议和关系图入口、个人分组与成员分类。
- 日志提交改用编辑业务日期；派发列表不再显示状态筛选/标签。截图暴露的工作伙伴横向拉伸已用明确尺寸与居中约束修正。
- 真实模式保持默认，Android 模拟器默认地址改为 10.0.2.2；新增 UI Demo / Android Backend 运行配置。注册使用公开部门接口 ID，注册/改密密码长度与服务端 12 字符最低要求对齐；连接失败给出后端/地址提示。

## 验证证据

| 检查 | 结果 |
|---|---|
| openspec.cmd validate --all --strict | 退出 0，13 passed / 0 failed |
| dart analyze --fatal-infos | 最终退出 0，No issues found；先集中修复本轮 lint 与已触及 Repository 的旧 lint |
| Flutter test --no-pub --dart-define=USE_MOCK=true | 退出 0，20 tests passed；mobile/test-stage3.log（忽略日志） |
| 原型 app.js 的 node --check | 退出 0，仅语法验证 |
| git diff --check | 退出 0，只有 LF/CRLF 提示 |
| SVG 渲染/人工查看 | 两图渲染退出 0，中文与分区可见；有字体缓存提示 |
| debug APK | Flutter quiet Gradle 客户端长时间无输出，改用 Gradle plain/offline 获取证据；最终状态补记于下方 |

Mock 测试包含任务幂等/越权拒绝/独立复核、导航、日志日期筛选、AI 草稿按账号隔离，以及全路由 360×640、412×915 + 字体1.5、800×1000 无布局异常。新增注册契约测试验证公开部门列表为 List 响应、提交 ID 而非名字、请求不含角色；网络错误测试验证提示。测试不代表真实后端或真实注册成功。

工具启动问题：沙箱禁止写 SDK 锁，batch/snapshot 起初无结果；取得 verbose 错误后改用正常权限。Flutter 自动版本检查 git fetch 卡住，清理仅本轮残留子进程并以 --no-version-check 执行。IDE 服务未停止。

## 未完成与限制

- 未检测到电脑 8080 后端监听，真实登录/注册不能运行验收。注册后待确认流程、强制改密路由守卫、会话恢复及服务端错误精细文案仍需后端联调。
- 无真机 TalkBack、键盘/减少动态效果人工验收和最终 Flutter 页面截图；截图中人物修复后未真机复查。
- Flutter 仍有部分硬编码色值、旧素材和非核心通用页面，尚未完全达到阶段 3 文档全部布局契约。组件状态专页、人物六姿态、关联来源严格校验、周重叠事件列分配/固定时间刻度等保持待办。
- 真实附件、AI 作业/流式、帮助反馈、统计导出与管理契约未因 UI 改动而完成。
- 手机月历单格宽小于48dp，但高度≥60dp，并有完整议程入口；需最终无障碍/可用性评审。
- 工作区存在之前的设计、未跟踪技能和原型等混合改动；未提交、推送或创建 PR。远程 Issue 未关联。

## 启动验收

在 Android Studio 选择 UI Demo，停止后重新运行，应默认导图并显示演示标记；不能只 Hot Reload。真实启动选择 Android Backend，先确保电脑后端 8080 可访问 `/api/health`，再注册选择实际部门；成功应为待确认员工，无权读取业务数据。
