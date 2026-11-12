# 后端验证与验收入口

需求验收目标见 [APP需求验收基准](app-requirements-acceptance.md)。本文件记录实际环境、命令、结果与限制，逐用例签收留在关联Issue；历史通过不外推到当前代码或线上环境。

## 消息缓存与定时再验证（2026-11-07，已部署，设备待验收）

在 PR #77 的 `472ac42e9aaca0f9d24cebf180e54dfd7d5485a8` 上修订。此前消息页缓存随路由销毁、回前台无变化的Session替换及初始SSE历史回放仍会导致重复请求；共享客户端本地合成429又使其他操作显示限流。此次采用先显示缓存再后台验证：同会话按查询保留分页、离页5分钟回收，有订阅且前台每30秒检查、相同请求合并；后台暂停，已有内容不因临时网络错误而清空。定时对已加载分页发送条件GET，未变304不下载列表或更新状态；历史分页边界变化只重建首屏，不混合两个OFFSET快照。点击已读后立即核对，真实401/403及切号/退出清缓存。首次SSE以当前序号为基线，其他业务仍按后续事件刷新；消息页不再受SSE全局失效驱动。常规回前台身份校验静默进行，身份/权限不变不替换Session，服务端始终重验权限；客户端不再合成429阻断业务操作，后台仍尊重服务端Retry-After。

依据为成熟查询库的缓存新鲜时间、保留时间、结构复用和后台验证机制，以及HTTP标准条件请求，复用现有Riverpod，不新增框架或迁移。30秒与5分钟是本项目可调整的默认取值，非企业统一标准；本次缓存仅内存，冷启动仍需首屏加载。参考：[TanStack Query默认行为](https://tanstack.com/query/latest/docs/framework/react/guides/important-defaults)、[Riverpod生命周期](https://riverpod.dev/docs/concepts2/auto_dispose)、[RFC9110条件请求](https://www.rfc-editor.org/rfc/rfc9110.html#name-if-none-match)。ETag在当前用户授权查询后生成，减少网络传输，不代表免除数据库查询；后续若证据显示查询成本过高，再考虑持久版本与真正增量协议。

- 规划阶段 `openspec.cmd validate --all --strict`：46项通过、退出0，`output/yellow-theme/notification-cache-spec.log`。
- Java21/Maven3.9.15：`mvn.cmd -B -f server/pom.xml -Dmaven.test.skip=true package`退出0，测试源码及执行均跳过；`output/yellow-theme/notification-cache-backend-build.log`。
- D:/flutter：`flutter.bat build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://39.96.84.51/api`退出0，assembleDebug成功；证据 `output/yellow-theme/notification-cache-mobile-build.log`，安装包 `output/yellow-theme/workpanel-notification-cache-debug.apk`。受影响差异检查通过。
- 业务提交 `6f2ec8e606b51799acf7a714efcee64121a2b1c6` 已部署；云端内外健康UP，消息接口200后携带ETag再次请求返回304、正文0字节，核对会话已退出。仅为必要发布连通性核对，不运行测试套件；设备页面/切号/后台定时/已读同步仍待用户验收。详见[云端部署](cloud-systemd-deployment.md)。

## 消息刷新与限流修复（2026-11-06，已部署，设备待验收）

基线 `3f9eb2d561e17a41f91fb22c80cbfd23da2361ff`，分支 `fix/53-notification-refresh`，关联 Issue #53。通知改为每页30条、显式加载更多，搜索/分类/未读筛选在服务端分页前执行，返回全量未读数及按当前任务/日志/审核权限读取的摘要。客户端移除逐条详情摘要请求；SSE事件2秒合并、刷新至少间隔5秒，按类型和对象刷新，连接成功/常规重连不再触发全局刷新，前后台重放保留尚未刷新的事件。限额仍为同账号120次/60秒，429返回剩余窗口的Retry-After，客户端共享冷却、缺失头默认60秒，不自动重放写入。无数据库迁移。

- Windows / PowerShell、Java21、Maven3.9.15：`mvn.cmd -B -f server/pom.xml '-Dmaven.test.skip=true' package` 退出0，JAR打包成功；证据 `output/yellow-theme/notification-refresh-backend-build.log`。测试源码编译及测试执行均跳过。
- D:/flutter：`flutter.bat build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://39.96.84.51/api` 退出0，assembleDebug成功；证据 `output/yellow-theme/notification-refresh-mobile-build.log`，导出安装包 `output/yellow-theme/workpanel-notification-refresh-debug.apk`，289315802字节。受影响文件的`git diff --check`通过。
- 规划阶段 `openspec.cmd validate --all --strict` 46项通过、退出0；证据 `output/yellow-theme/notification-refresh-spec.log`。本批只做编译验证，不运行测试套件、数据库/API或设备链路验收；分页变化、权限收回、通知密集到达、前后台重放与429恢复待用户验证。
- 需要先更新后端以支持新的筛选和摘要，再安装对应APK；旧后端只提供旧字段，无法兑现完整筛选。用户随后明确授权将本次修复推送云端，提交仅纳入消息刷新修复；工作区既有指标JSON、Android运行配置及依赖锁文件的无关改动保留。实际部署结果见云端部署记录与对应PR。
- 代码提交 `bec842266a5be42e4d0587e065c3b4e5a30f569e` 已部署，草稿PR #77，未合并main。镜像、线上JAR哈希一致，服务active/running、NRestarts=0，公网健康UP；登录后新版通知分页接口200，summary/unread字段存在，核对后退出会话。实际库与旧JAR已备份，迁移SQL未变化，未运行测试套件。详见[云端部署](cloud-systemd-deployment.md)；发布核对不等于刷新功能设备验收。

## 月历、日志与统计布局修复（2026-11-06，未发布）

基线 `983b7e76ec1532df5ac7a59bbf86197cff61e8ba`，分支 `fix/53-calendar-cell-overflow`，关联 Issue #53。月历各周统一预留五行显示空间，超过五项时前四项加右下角黄色 `+N`，今天右上角显示角色；移除创建任务按钮下方的整行占位。日志近三天查询原被转换成起始日的单日查询，现本人日志与下属日志均保留明确的 `from/to`；编辑器保持同一输入框，取消因键盘高度主动失焦，右上角下属日志入口使用单行自然宽度。统计页周期居中在上、日期及唯一筛选入口在下，并同步现有 HTML 原型。接口、权限与数据库未改。

- Windows / D:/flutter：`flutter.bat build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://39.96.84.51/api` 退出0，assembleDebug 成功；证据 `output/yellow-theme/calendar-diary-statistics-build.log`，导出安装包 `output/yellow-theme/workpanel-calendar-diary-debug.apk`。
- `openspec.cmd validate --all --strict` 46项通过、退出0；受影响文件的 `git diff --check` 通过。按用户要求未运行测试套件或设备操作；日历溢出、手机输入与日志提交显示、统计筛选交互均待用户手工验收，编译不代表功能验收通过。
- 无后端修改，未重新部署。用户后续明确要求提交PR并合并；本批提交仅包含上述修复及年度登录表补全，既有指标JSON、Android运行配置及依赖锁文件的无关修改保留在本地，不纳入提交。合并状态以远端PR为准。

## APP验收对齐修复（2026-11-05，尚未合并发布）

基线为 `e5bc21557618a8c1d331eea3ab5578b8661d70f0`，分支 `fix/53-app-acceptance-alignment`；关联Issue #53、#28、#58、#60、#63。用户明确的三项覆盖旧要求：任务管理只读完成情况、五行折叠、同页人员树。任务和证据分别维护在对应OpenSpec与本入口，不新建平行验收报告。

- A/H：补齐近三天上海业务日分区、跨午夜/回前台/提交/通知刷新、历史筛选，恢复任务管理完成情况及真实派发时间、多人员/多标签折叠；摘要非消息区域可进入完整列表。完成情况来自服务端正式phase，未知/空值不伪装完成；dispatchAt只取真实派发事件。列表权限和派发表单禁状态不变。
- B：同页部门→团队→人员树，稳定ID多选确认/取消、搜索路径、会话失效及小屏键盘避让；沿用服务端组织和标签校验。
- C/D：≤5项全显，>5前4项与总数减4的+N；完整日清单、邻月只读任务、跨周同ID、独立节假日/候选行，保留抓取日、版本、幂等和审核策略。
- T：现有独立本人todo和任务看板链路复验；新增修复跨客户端完成排序/数量变化后的OFFSET分页漏项。检测不一致后保留列表并自动重读一次，失败可手动重试，旧会话响应被丢弃。
- 恢复来源：核对 `4a1885fd1833f2073903095879b5f616ffc78ef5` 的patch和完整树，不包含近三天或完成情况列。相应代码在 `C:/Users/念/.codex/worktrees/member-a-verification/Grade3_Work` 的未提交修改中；仅只读参考，未改该工作树，不能据指定SHA断言合并丢代码。

环境：Windows/PowerShell、Java21、Maven3.9.15、D:/flutter、Docker隔离PostgreSQL/Redis/Neo4j；Android模拟器Pixel_8_Pro另行运行。证据均在忽略的 `output/`，其中fixture与临时定义含合成测试凭证，不提交或外传。

| 检查 | 本批实际结果 | 证据位置 |
| --- | --- | --- |
| `scripts/test-backend.ps1 -KeepContainers` | 退出1；513项，1失败、2错误、1跳过。失败为本批派发时间断言比较毫秒JSON与微秒DB，已修正；2错误为年度场景既有日期缺陷，见#73 | `output/app-acceptance/backend.log`、`backend-initial-reports/` |
| 干净隔离后端重点复验 | 通过MAVEN_ARGS选择BackendIntegrationTest、TaskDispatchIntegrationTest、TaskQueryServiceTest、OpenApiSerializationTest、PersonalTodoIntegrationTest、MultiFounderReviewIntegrationTest、OrganizationIntegrationTest，再执行原test-backend脚本；95项全部通过、退出0，JAR打包成功 | `output/app-acceptance/backend-clean-recheck.log` |
| `flutter analyze --no-pub` | 全项目最终无问题、退出0；末次todo边界修复后两文件定向分析通过 | `output/app-acceptance/flutter-final-analyze.log`、`todo-partial-refresh-analyze.log` |
| `scripts/test-flutter.ps1 -Flutter D:/flutter/bin/flutter.bat` | 最终HTTP55、Mock403通过；6个opt-in跳过，退出0；此后仅末页失败边界一处修正，按下一行定向补验 | `output/flutter-regression/{http.log,mock.log,exit-codes.json}` |
| todo并发分页定向回归 | 先18项通过，再补三页局部刷新/末页失败回归，最终19项通过、退出0；覆盖重排、总数变化、重读失败重试、切号以及61条稳定列表保留 | `output/app-acceptance/todo-partial-refresh-test.log` |
| `scripts/test-home-todos-live.ps1` | 退出0；Flutter UI→真实HTTP→PostgreSQL，事项新增/重登/完成恢复/跨日编辑/删除、他人不可读写、甲乙12条共同参与任务及外人空看板；运行时OpenAPI重新导出 | `output/workpanel-home-live-d86649e8a5/` |
| `scripts/test-calendar-live.ps1 -SkipBuild -CrowdedTarget -Device emulator-5554` | 两次退出1，均未完成正式移动/审核链路；连续取消后的再次长按失败，第二次有坐标/状态和截图诊断。设备图像与采样日期错位，尚不能确认产品/测试根因，不计Android通过 | `output/calendar-live-375094a7ab/`、`output/calendar-live-c179c4c309/` |
| 真实HTTP release APK | 构建退出0；0.1.6 / 20261109，120976423字节；apksigner验证退出0，为Android Debug内部测试签名；API为仓库现有 `http://39.96.84.51/api`，未部署本批后端，不能代表匹配环境签收 | `output/app-acceptance/releases/pandora-app-acceptance-0.1.6.apk`、`apk-release.log`、`apk-signature.log` |
| `npm ci` / `npm run build` | 均退出0 | `output/app-acceptance/web-{install,build}.log` |
| `openspec.cmd validate --all --strict` / 文档链接 / 差异 | 46项通过、退出0；28份受影响Markdown的本地链接无缺失；最终diff另在提交前复核 | `output/app-acceptance/openspec-final.log` |

候选APK SHA-256：`2e5da45a871506babaaf382ff9b31042a895cc169ee56cacfedb47a2e95b088c`。仅本地构建，未发布；正式候选须从实际合并提交重建并使用匹配后端验收。

后端第一次定向复验曾复用已初始化测试库，因初始管理员密码已变更产生级联失败（`backend-recheck.log`）；未以此修改认证或放宽测试。上表95项结果来自重新创建并清理的干净隔离数据环境。

非功能已覆盖安全/隐私（跨公司、待确认、本人todo与组织隔离、自审禁止）及可靠性（幂等重放、版本冲突、并发审核/重路由、跨页一致性恢复）；这不替代设备性能与TalkBack人工验证。

未解决：Issue #73 的年度V1演示初始化随日期滚动插入空审核人，新空库显式annual-2026和完整后端回归仍阻塞；不改已发布V1、不伪造夹具掩盖。Android拖动集成链路尚未通过；非作者审阅、合并提交干净构建、实际候选APK全部41项签收、实体设备/TalkBack及完整人工/性能矩阵仍未完成。本批未合并、未部署，不宣称全部APP验收通过。

2026-11-05 首页样式与入口定向增量：删除每日事项右下方日期按钮，年月标题打开1900–2100年月滚轮，确认切到所选月1日、取消不变；双摘要改低饱和信纸细横线/小折角；移除日志页任务管理快捷按钮。Windows/D:/flutter 下，`flutter test --no-pub --concurrency=1 test/personal_todos_test.dart test/home_prototype_layout_test.dart test/home_summary_navigation_test.dart` 34项通过、退出0；`flutter test --no-pub test/recent_logs_acceptance_test.dart` 6项通过、退出0；受影响4份源码、首页主题及2份测试的定向 `dart analyze` 无问题、退出0。覆盖320/360/390/480宽、1.0/1.5字号、年月确认/取消/上界、事项与摘要交互及日志原功能；源码差异检查通过。日志见 `output/home-prototype/home-stationery-{recheck,logs-test}.log`，Flutter截图 `output/home-prototype/flutter-390-top.png`。首次统一运行被主线程正在编辑的人员目录fold类型错误阻塞，修复由主线程完成后日志测试已复验通过；初次年月测试控件定位错误也已更正复验。此增量尚未独立重建/安装APK，未提交或推送，工作区包含其他并行修改，不把组件截图当作真机验收。

## 公司月历节日本日与离线兜底（2026-11-05，未发布）

沿用 `fix/53-app-acceptance-alignment` / HEAD `e5bc215` 的未提交工作区，关联既有Issue #60。用户本次要求覆盖旧星标/逐日假期名称：只在节日本日显示名称，无星标；联网取现有公告的休/班并持久缓存，断网以缓存和本地历法兜底，不推算行政调休。服务端接口/数据库未改，新增锁定依赖lunar 1.7.8（MIT，许可证随客户端保留）；最终产品口径见[月历主题](member-d-calendar.md)。

- Windows/PowerShell、D:/flutter（3.38.7），`flutter test --no-pub --dart-define=USE_MOCK=true test/holiday_data_test.dart test/member_d_calendar_test.dart test/calendar_month_preview_test.dart test/calendar_preview_lane_test.dart test/calendar_drag_widget_test.dart`：56项通过，退出0。覆盖2024–2026公农历/清明、除夕、重合/闰月、1900/2100边界、跨年、联网/断网/缓存损坏/存储失败、360dp及1.4倍字号、五行折叠与拖动候选。证据 `output/app-acceptance/holiday-tests-recheck.log`。
- `flutter test --no-pub --dart-define=USE_MOCK=false test/holiday_http_test.dart`：1项通过，退出0；真实StreamProvider→HttpRepository/Dio→合成HTTP适配器及SharedPreferences测试存储，验证既有URL/相邻年度查询、跨provider会话恢复、联网刷新及缓存不含token。未连接真实供应商，也不等于Android系统持久存储已验收。证据 `output/app-acceptance/holiday-http-test.log`；已加入 `scripts/test-flutter.ps1` 的HTTP分组。
- 初始 `flutter analyze --no-pub` 全项目无问题、退出0；最终布局修复和HTTP测试补齐后，`dart analyze` 对两个受影响实现和三个测试文件无问题、退出0。证据 `holiday-analyze.log`、`holiday-final-analyze.log`。`openspec.cmd validate --all --strict` 46项通过、退出0，证据 `holiday-openspec.log`。
- 初轮55项通过、1项长任务拖动失败：新增提示行改变网格高度。已把提示移至现有星期标题装饰区域，保持网格高度与命中几何，再执行完整上述56项全部通过，未改拖动断言。安全/隐私验证公共缓存不含token；可靠性验证慢网立即显示本地节日、无缓存/坏缓存/磁盘失败和重新联网恢复。
- 未进行本轮后端全量回归、APK重建、真实上游/实体Android断网重启、TalkBack或正式部署；仍须按D04/D05人工签收。工作区含本轮前已有大量混合改动，依据AGENTS自动推送前置规则，不自动提交或推送整个工作区，保留原有改动。

## 任务表格、表单对齐与消息摘要（2026-11-05，未发布）

工作区沿用 `fix/53-app-acceptance-alignment` / HEAD `e5bc215`，保留已有混合改动。参与人改用主题浅色胶囊、标签未选中即可预览服务端背景色、共用派发表单字段名按图标高度居中。检查共用SectionHeader、通用表单、事项编辑及日志标题后，其他既有居中行/标准label布局未发现相同顶部字段名问题。消息副标题优先已有内容，否则复用授权详情读取及itemProvider缓存刷新，失败明确提示，不新增接口/迁移。

用户中途明确要求停止测试，仅确认编译，由用户自行验收。此后未继续执行测试；先前测试过程不作为本轮完整签收结论。`flutter build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://127.0.0.1:8080/api` 实际退出0，Gradle assembleDebug成功，产物 `mobile/build/app/outputs/flutter-apk/app-debug.apk`，220308865字节；日志 `output/app-acceptance/ui-details-build.log`。API需模拟器 `adb reverse tcp:8080 tcp:8080`。本轮没有安装/人工操作验证、发布、提交或推送；真实界面、读屏和消息名称由用户安装签收。

### 标签颜色覆盖及节日标题位置补修

随后按用户截图修复Material3全局ChipTheme.color覆盖单个标签背景的问题：FilterChip显式设置各状态为目录颜色，文字及勾选按底色明暗显示，去除表面染色。节日本日名称移至日期数字右侧同排加粗，窄格缩放，休/班独立放到下方；任务行及折叠计算不变。继续遵循用户只编译、不测试的要求。同一真实HTTP/本地8080参数执行 `flutter build apk --debug --no-pub`，退出0、assembleDebug成功；日志 `output/app-acceptance/label-colors-calendar-header-build.log`。当前同路径APK为258263674字节，替代上一包；未执行测试或安装签收。混合工作区不自动提交/推送。

后续按用户截图将休/班固定于日期格右上角，并按系统字号为日期/加粗节日名称预留标记宽度，禁止换到下一行；上段“下方”布局为已替代版本。仍只执行同参数Debug APK编译，退出0，日志 `output/app-acceptance/calendar-corner-badge-build.log`；同路径APK已更新，未执行测试或安装验收。

## 五个 PR 集成与发布（2026-11-04）

本批次整合 #55/#57/#59/#61/#62，基线 main `afbdfce`，独立工作区 `chore/integrate-five-prs-20261104`；保留原工作区未提交改动，用户授权本次 Agent 审阅后合并。#59 日历已由 #65/#67 接入，保留 main 的 V27、完整任务行、落点及限流修复，整合原分支祖先关系和管理后台依赖。

- 升级选择追加 V28 创始人互审、V29 个人置顶、V30 多标签，不采用 Flyway out-of-order、不改已发布迁移。年度场景 V2 为第二创始人，V3 为多创始人协作；正式部署保持场景初始化关闭。
- 普通任务列表支持本人置顶排序；日历继续使用原日期顺序和快照，保留权限判断。多标签兼容旧零/单标签幂等摘要，异内容仍拒绝；管理后台审核接入当前 expectedVersion 校验。
- 节假日独立占行，故障不阻塞任务。#61 旧五行折叠设计由本日已发布的完整任务行要求替代。原日历设备性能、TalkBack 与人工矩阵缺口继续保留。
- 线上运行 systemd JAR；旧 Compose CI 部署仅在 workflow_dispatch 且 DEPLOYMENT_MODE=compose 时显式启用，避免合并时启动第二套 API。
- Windows PowerShell、Java 21、Maven 3.9.9、Flutter 3.38.7；真实隔离 Docker PostgreSQL/Redis/Neo4j。Docker 遗留通信目录改名保留，未重置数据卷。另建本机临时 PostgreSQL 仅用于预备诊断，未用于当前 Docker 验收。
- 最终验证（2026-11-05，Issue #69）：`scripts/test-backend.ps1` 退出 0，511 项、0 失败、0 错误、1 跳过，Maven clean verify / Spring Boot JAR 打包成功；`scripts/test-flutter.ps1 -Flutter D:/flutter/bin/flutter.bat` 退出 0，HTTP 50 项、Mock 373 项通过，5 项需要真实服务的 opt-in 测试跳过。`flutter analyze --no-pub` 无问题、退出 0；`npm ci` / `npm run build` 退出 0；`openspec.cmd validate --all --strict` 52 项通过、退出 0。
- 首轮失败已修复：审核测试补齐 expectedVersion、多标签扩展返回契约、去除重复关系夹具；AI 依赖失败测试在构造事项/步骤/回执期间暂停调度，避免夹具尚未构造完即被后台结算。月历保留完整任务行，测试点击日期空白位置；选择人员测试按新版组织搜索操作；日期筛选夹具跟随当前月份；外部测试容器在组件卸载时释放，避免遗留定时器。无屏幕尺寸的月历容器增加有效高度兜底，原卡住的组件测试及全量回归通过。
- JAR：`server/target/collaboration-server-1.0.0.jar`，SHA-256 `d3b002875e0f893a4d13d8cb83ac467d6aabb1cbdf098a17f913ac7631713183`。过程日志与界面截图保存在忽略的 `output/`；外部 DeepSeek/OCR、实体设备、TalkBack 和性能人工矩阵仍未补验，不能用本轮自动测试替代。
- 安全验收关注跨公司、待确认账号、自审、版本和个人置顶隔离；可靠性关注并发一次生效、同键重放、V27 向前升级及节假日故障降级。
- 已取得用户授权的服务器会话。部署须先核对实际数据库、保存并验证备份、逐字节比对已发布迁移，再替换 JAR、重启及检查健康和业务数据摘要；实际部署回执在执行后补录。

## 验证方式

在仓库根目录执行；需要 Java 21、Maven 与 Docker，环境和参数以脚本为准：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
# 本机资源受限时使用 Docker Maven
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven
```

脚本使用隔离资源，不应将实际业务数据库作为测试目标。镜像冒烟、真实 HTTP 场景、专项验证和灾备工具见 [脚本索引](../scripts/README.md)。需要维护 OpenSpec 时执行规范校验；简单修改按 [开发流程](development-workflow.md) 选择受影响检查，不为验证过程单独创建文档或 change。

## 当前待处理项

### 前批草稿 PR 验证记录（2026-11-06，69f6c60）

工作分支 `fix/53-app-acceptance-alignment`，比较基线 `e5bc21557618a8c1d331eea3ab5578b8661d70f0`；包含上述验收修复及随后首页、人员目录UI修改。前文APK及旧批次通过记录不能代表最新工作树已通过完整验收。

- 最新 `scripts/test-flutter.ps1 -Flutter D:/flutter/bin/flutter.bat`：HTTP56项通过、退出0；Mock447项通过、6项opt-in跳过、4项失败、退出1。证据 `output/flutter-regression/{http.log,mock.log,exit-codes.json}`；人员目录旧平铺与部门下拉两项断言已按批准的目录交互更新，随后定向复验通过；另两项 `member_d_calendar_test` 的联网/缓存离线布局仍有右侧14px溢出，未解决。
- `flutter test --no-pub --dart-define=USE_MOCK=true test/personnel_directory_test.dart test/management_analytics_http_test.dart test/week5_ui_acceptance_test.dart --reporter expanded`：24项通过、退出0，覆盖原记录条/资料路由、目录身份分组和搜索、失败重试、320dp/大字号及选择清空。证据 `output/home-prototype/people-implementation/affected-regression.log`。上述旧断言修正后未重跑完整回归，不能将原全量结果改写为全通过。
- 人员目录定向分析无问题、退出0，规划阶段OpenSpec严格校验46项通过、退出0；证据 `output/home-prototype/people-implementation/{analyze.log,openspec-plan.log}`。最新整批静态及规范检查以PR补充的实际结果为准。
- PR整理时再次严格校验：46项通过、退出0，证据 `output/pr-openspec.log`。全项目分析首轮退出1，仅发现首页及其测试3处缺少if花括号的info；已补充花括号，不改变分支行为。`flutter analyze --no-pub` 复验无问题、退出0，证据 `output/pr-flutter-analyze-final.log`；该纯样式补修后未重跑业务测试或重建APK。
- 人员展示保留原记录条与导航，选择器沿用服务端授权分页和资格筛选；没有新增数据库迁移。此次最新UI未重新构建安装APK、未完成设备人工验收；后端95项重点复验、年度初始化#73、真实Android拖动阻塞仍按前文范围记录。

2026-10-30 的 442 项、49 失败、1 错误，以及此前整合批次的511项、零失败零错误均为历史结果。本批完整回归与重点复验以文首APP验收对齐记录为准，年度初始化#73和Android月历链路尚有阻塞；目标设备、外部DeepSeek/OCR、性能与无障碍仍有未验收范围，保留对应历史记录中的具体限制。

历史测试 JVM 等待退出后被强制结束的诊断仍见 [专项安全回归](member-b-security-regression.md)；构建成功不能据此宣称优雅退出已验证。旧数据库转换只允许按工具支持的已知历史先备份、恢复副本再校验，不改写已发布 Flyway 脚本或直接 repair 业务库。

后续结果更新现有主题文档或 Issue/PR，必须提供代码基线、环境、命令、明确退出码、结果及限制。过程日志与截图放被忽略的 `output/`。此前仓库文档清理没有运行功能测试、部署或修改数据库；本批修复的测试范围见文首，不继承清理批次的状态。

### 黄色主题与年度增量：当前编译和数据库核对（2026-11-06）

沿用 PR #74，previous head `69f6c60f1b4eb6182f3ca89056bd1a563d7cfcad`。本次按用户要求不运行测试套件，历史测试失败记录不能改写为通过。

- `mvn.cmd -B -f server/pom.xml '-Dmaven.test.skip=true' package`：退出 0，JAR 已生成；证据 `output/yellow-theme/member-enrichment-backend-build.log`。
- `flutter.bat build apk --debug --no-pub --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://39.96.84.51/api`：退出 0；证据 `output/yellow-theme/public-mobile-build.log`。这是公网后端版本，设备运行未验收。
- 本地实际数据库 V4–V6、云端 V2–V6 已成功；两边主公司创始人均 4 名，场景成员未分配 0、在职个人资料缺失 0，每位在职普通员工有 8 条新增月历重叠计划（本地10人、云端9人，保留既有审批状态）。备份及执行证据见[年度场景](annual-scenario-rebuild.md)。
- 原月历折叠/拖动逻辑保持；统计页、黄色主题、各子页及历史 14px 溢出等仍需用户设备验收，未将编译当作功能验收。PR #74 已合并，云端 API 重启后内网/公网健康检查 UP，公网 APK 已覆盖安装模拟器；云端 raw 网络故障及双入口修复另按实际发布记录跟踪。
- 后续双入口修复：`mvn.cmd -B -f server/pom.xml '-Dmaven.test.skip=true' package` 退出0；`openspec.cmd validate --all --strict` 46项通过、退出0，证据 `output/yellow-theme/holiday-fallback-{build,spec}.log`。部署诊断在云端用相同 Java HTTP 设置读取 Contents 返回200、2026年39条安排，raw入口超时；没有把探测程序当作测试套件或完整功能验收。最终公网接口结果以修复PR发布记录为准。


## 个人资料与首页修正（Issue #84）

2026-11-12，Windows、Flutter/Dart（D:/flutter）、Java21、Maven3.9.9。实现验证提交 `94a5e9d29643954d7c4832f75d35a38a6bb929d3`，基于 OSS 分支 `f21e812a7c9bf9acccd933f380b9050f8ae3ebc8`，本段后续提交仅同步规格与验证记录。性别为男/女选填，非法写入拒绝，历史非标准值资料接口显示为空但保留数据库原值；任务预览三条真实数据；删除重复可见性提示；工龄按上海业务日期显示年月天。无新接口、迁移或部署。

- `flutter test test/profile_choice_test.dart test/tenure_test.dart test/home_summary_navigation_test.dart test/home_prototype_layout_test.dart test/home_daily_todos_visual_test.dart test/week6_client_contract_test.dart`：46项通过，退出0。覆盖选择/取消/保存、请求条数、0至4条实际数据、320px及1.6倍字体、完整首页布局、空态与重试、日期边界。日志 `output/profile-final-flutter.log`。
- `MAVEN_ARGS=-Dtest=MobileDataContractIntegrationTest,TaskPinIntegrationTest,MobileP0MigrationUpgradeTest` 后执行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`：13项通过，退出0，JAR构建成功；隔离容器与真实PostgreSQL，日志 `output/profile-backend-scoped.log`。性别男女回读/空值/缺席保留、非法值不改变版本、历史值保留，以及既有组织权限与版本冲突通过。
- 受影响的工龄、资料页、预览卡片、每日事项及新增/修改测试执行 `dart analyze <paths>`：无告警，退出0；全项目 `dart analyze` 退出2，剩余16项既有问题（2 warning、14 info），没有 error，见 `output/profile-final-analysis.log`。基线无关告警未扩展修复。
- `openspec.cmd validate --all --strict`：47项通过，退出0；`git diff --check` 通过。
- 正式默认模式中 `profile_dog_ui_test.dart` 访问未配置服务导致旧断言失败；按该演示测试所需 `--dart-define=USE_MOCK=true` 重跑通过。临时截图脚本及该测试合计3项通过，证据 `output/profile-capture.log`、`output/profile-verified.png`；截图使用本机中文字体替代测试字体，未启动OSS资源加载，仅验证资料布局，不能作为生产素材/设备验收。
- 全量后端首轮在年度数据迁移夹具出现2个既有错误，随后进入无关AI等待，采集线程栈后主动中止（退出1），没有宣称全量通过。证据 `output/profile-backend.log`、`output/profile-threads.log`；受影响测试另行通过如上。
- 非功能：安全验证资料读取范围、非法请求不写入与版本控制；易用性验证窄屏/大字/独立详情入口，无溢出。
- 尚未验证：Android真机、线上发布及完整后端套件成功；本轮未创建或部署APK。保留既有OSS资源加载方式，PR依赖OSS分支 #81。

## 阿里云 Android 必要通知（Issue #86）

2026-11-12，基于 `31f2df2cafe362d56ac446cd64f8f20d5d24f787` 的功能分支；本段记录同批实现的本地验收。提案、范围及外部未完成项由 [android-essential-push](../openspec/changes/android-essential-push/tasks.md) 维护。未提供EMAS/RAM/厂商/正式签名配置，本轮不部署、不发真实云推送；ACCEPTED只表示供应商受理。

- Windows、Java21/Maven3.9、隔离Docker PostgreSQL16，`powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -Tests PushRulesTest,AliyunPushGatewayTest,EssentialPushIntegrationTest,TaskRevisionServiceTest,TaskLifecycleServiceTest,TaskDispatchServiceTest,TaskComponentsTest,TaskDispatchIntegrationTest,ReviewIntegrationTest,MultiFounderReviewIntegrationTest,BackendIntegrationTest`：119项通过、退出0，JAR构建成功；`output/push-backend-final.log`。随后仅扩展测试覆盖24h/1h/逾期各阶段及真实HTTP撤回入口，`-Tests EssentialPushIntegrationTest` 11项通过、退出0（`output/push-backend-scenarios.log`）；厂商参数更正为官方OPPO分类/Honor通道后，`-Tests AliyunPushGatewayTest` 2项通过、退出0（`output/push-provider-final.log`）。上述测试总计120个不同用例；受影响既有资料/置顶测试此前同批8项也通过，非全量后端验收。
- 真实任务HTTP入口→审核生效→outbox→站内通知/推送队列→受控gateway→点击授权通过；额外覆盖事务回滚无部分通知、重复处理、会话撤销、换号lease、他人/他司拒绝、待确认仅本人入职结果、旧审核步骤取消、过期/分类关闭、静音延后、任务版本变化和最多5次重试。供应商层另以真实官方Java SDK向本机HTTP服务签名发送并检查通用摘要/参数，未调用阿里云；两层测试不等于云端端到端送达。
- Flutter3.38.7/Dart3.10.7，`flutter test --no-pub --concurrency=1 test/push_notifications_test.dart test/week6_client_contract_test.dart test/review_notification_display_test.dart --reporter expanded`：22项通过、退出0（`output/push-flutter-final.log`）。覆盖冷启动点击等待绑定、换号/同账号并发、退出、销毁后回调、拒绝权限、缺配置、保存失败、白名单目标及320px设置布局。受影响6组路径的 `dart analyze` 无问题、退出0（`output/push-dart-analysis.log`）。
- `flutter build apk --debug --no-pub --dart-define=USE_MOCK=false`：退出0，原生SDK/receiver/PopupActivity/权限与channel编译成功（`output/push-android-build-final.log`）；产物 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。无真实配置，安装包不代表离线推送可用，不调整既有素材打包配置。
- 扩展运行calendar_notification_refresh/live_notifications_contract/notification_preview三组测试失败，其中8项在未修改的基线副本可复现（`output/push-baseline-tests.log`）；旧预览测试仍期望已移除的逐条详情读取，SSE断言仍期望旧刷新语义。此次新增的一处post-frame读取已销毁provider问题已修复，对应 `actual recovery inbox renders` 单项通过、退出0（`output/push-lifecycle-recheck.log`）。最终重新运行这三组测试为8项通过、8项失败，失败用例与基线一致（`output/push-legacy-recheck.log`）；未宣称扩展套件或全项目全部通过。
- 窄屏设置页截图 `output/push-settings-unconfigured.png` 已目检无溢出；临时截图测试退出0（`output/push-capture.log`），使用本机中文字体，不是设备截图。安全/隐私证据为当前会话/组织范围再授权、仅发送通用摘要且签名请求不含RAM secret；可靠性证据为事务回滚、去重、时效和有限重试，云调用采用独立调度线程。
- OpenSpec严格校验48项通过、退出0（`output/push-spec-validation.log`）；差异检查通过。真实前台/后台/锁屏/进程回收/离线恢复、厂商通知分类和系统权限手动操作均未验收，任务5.1/5.2保持未完成。回滚先关PUSH_ENABLED并关闭App通知，保留V34及表；最终整合须先统一基线和并行分支既有V31–V33迁移。
