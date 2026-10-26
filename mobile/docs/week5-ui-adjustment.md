# 第五周九张批注：前端 Mock 调整与验收

日期：2026-10-17。分支：`HCJ`。变更：`frontend-requirements-adjustment`，独立任务 UI.1–UI.6。

## 范围与依据

用户最新明确要求先完成前端设计与 Mock 交互，后续替换真实接口。本批次以最新九张批注截图为直接依据，旧 DOCX 与原 OpenSpec 中未覆盖的后端、Web、素材任务继续保留。本报告中的“通过”仅指指定 Mock/页面测试和设备检查。

沿用 Riverpod → Repository → MockRepository，避免页面直接写死数据。未修改服务端、数据库、Web 或新增网络服务；既有 HTTP repository 的早期改动仍在工作区，本批次未把它们作为真实联调通过的证据。Mock 的组织范围演示不代替后端权限边界。

工作区已有 README、doc/docs 整理和此前 Flutter 改动，均保留。未提交、推送或创建 PR；依据 AGENTS.md，混合用户改动禁止自动推送。远程 Issue 编号待关联，本地范围、优先级和验收已记录在本变更。

## 逐图对照

截图文件均为用户提供的 `codex-clipboard-<编号>.png`，原件在 Windows 临时目录。下表证据位于本文件同级 `evidence/week5/`。

| 图号及文件编号前缀 | 批注要求 | 已接入的前端实现 | 验收证据 |
| --- | --- | --- | --- |
| 1 / 47165fa5 | 四卡片两行两列、拉高；删除标题下灰字日期 | `dashboard_home.dart` 两列可滚动布局；按高度增加标题；公司任务过滤本人接收且预览最多10条 | `01-dashboard-390.png`；`device-dashboard.png` |
| 2 / 42f4a512 | 公司任务列表取消欢迎卡、搜索、分段、筛选工具 | `/tasks/received` 独立 ReceivedTasksPage，仅接收任务卡片，可点详情 | `02-company-tasks-390.png`；`device-company-tasks.png` |
| 3 / 5eea3dee | 删除月历下方重复记录列表，主体拉长铺满 | 月历按剩余视口计算行高；点击日期打开全部记录弹层；多记录用短标题与剩余数 | `03-month-390.png`；`device-month.png`；日期弹层 widget 测试 |
| 4 / 8ec0ef78 | 周历拉高，每日至少两条预览 | 七天等分剩余高度，每天两条全宽预览与剩余数；底部留加号空间 | `04-week-390.png`；`device-week.png`；逐日两条断言 |
| 5 / 9ad3951f | 姓名/日志搜索，部门和日期同排，作者姓名头像 | 部门分组日志时间线；统一下拉框；头像姓名与详情/个人日志入口 | `05-subordinate-logs-390.png`；`device-subordinates.png`；组合筛选测试 |
| 6 / b270f076 | 删除底部胶囊，右下加号；可修改日志点击即编辑 | 新建/继续当天日志；草稿及24h内日志直达表单，右侧箭头打开详情 | `06-logs-390.png`；`device-logs.png`；草稿到修改完整 widget 链路 |
| 7 / 742e59be | 底部提交/修改/24h后灰色；公开评论回复 | LogEditWindow 与定时刷新；Mock写入复核窗口；任务/日志共用 PublicComments | `07-log-detail-390.png`、`11-locked-log-390.png`；`device-log-comments.png`、`device-comment-posted.png`；窗口与评论测试 |
| 8 / fe2ac44a | 仅保留人员展示索引，删除重复页面路由 | 删除组织索引页；移除 `/me/team`、`/me/organization` 索引路由，保留成员详情与日志路由 | `08-profile-390.png`；`device-profile.png`；layout及成员入口回归 |
| 9 / 7278683c | 人员页增加部门筛选 | `/me/people` 搜索与部门组合过滤、分组成员卡片；本人进入本人资料 | `09-personnel-390.png`；`device-personnel.png` |
| 最新文字补充 | 我的新增独立任务管理，查看本人及下属所有任务 | `/me/tasks` 对所有已授权返回任务提供管理列表；本人接收/发布分段、搜索、字段筛选、紧凑视图、详情 | `10-task-management-390.png`；`device-task-management.png`；员工入口与递归下属范围测试 |

公司任务列表按图2移除工具栏；个人任务管理是独立新页，保留管理工具。全部任务包含仅下属参与、本人未参与的任务。普通员工也有入口，范围提示为“本人的全部任务”，不显示派发按钮。

2026-10-18 最新要求已覆盖本轮早期月历行为：日/周/月只显示任务；月历每天最多三条、跨日固定轨道色带、整月无需纵向滚动。原先小屏滚动及剩余数提示不再适用。最新实现、命令、截图与设备限制见 `calendar-task-view-2026-10-18.md`。

## 日志与演示数据规则

- 首次提交成功时写 `submittedAt`；24h 内保存正文不重置该值，不产生审核/版本列表。
- `now == submittedAt + 24h` 即锁定，Mock拒绝写入，详情按钮变灰；编辑页保存禁用并阻止字段输入。提交时间未知时保守禁用。
- 显式保存草稿写入 Mock，同时加密保存在本机；自动保存继续使用原本地草稿存储。重复提交同日已提交日志会拒绝；每人每日最多一份日志。
- 公开评论包含头像、姓名、时间、正文，支持回复引用；空评论、无效父评论、评论修改/删除被拒绝。评论不递增正文版本，避免制造正文冲突。
- `managerId` 表达递归下属，员工仅显示本人；下属日志排除本人、草稿和范围外记录。
- 本周每天有10条不同任务，日志按成员与业务日期去重。Mock 的无时区种子时间按上海业务时间过滤，避免UTC设备漏掉周日；首次提交时间仍使用真实时刻。新任务列表和评论区统一显示上海时间，不跟随设备UTC时区偏移。
- Mock 数据保存在进程内，重启后业务演示数据重置；本机加密草稿按原机制保留。APK与页面标注演示数据。

## 验证环境与命令

Windows / PowerShell；Flutter `3.38.7`、Dart `3.10.7`。SDK：`D:\flutter`，依赖缓存：`D:\FlutterPubCache`。

在 `mobile/` 下运行：

```powershell
$env:FLUTTER_ROOT='D:\flutter'
$env:PUB_CACHE='D:\FlutterPubCache'
$dart='D:\flutter\bin\cache\dart-sdk\bin\dart.exe'
$flutterTool='D:\flutter\bin\cache\flutter_tools.snapshot'
& $dart analyze
& $dart $flutterTool --suppress-analytics test --no-pub --dart-define=USE_MOCK=true test/week5_mock_workflow_test.dart test/week5_ui_acceptance_test.dart test/layout_test.dart test/member_workspace_contract_test.dart test/live_notifications_contract_test.dart test/management_analytics_http_test.dart --reporter expanded
& $dart $flutterTool --suppress-analytics build apk --debug --no-pub --dart-define=USE_MOCK=true
```

在仓库根目录运行 `openspec.cmd validate --all --strict` 与 `git diff --check`。诊断输出位于 `.diagnostics/week5-*.log`。

最终命令结果（均取得明确退出码0）：

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| `dart analyze` | No issues found | `.diagnostics/week5-analyze.log` |
| 上述6个测试文件 | 45项通过，0失败 | `.diagnostics/week5-tests.log` |
| 最后时间展示修正后的2个week5测试文件定向回归 | 12项通过，0失败 | `.diagnostics/week5-final-ui-tests.log` |
| Mock debug APK | assembleDebug成功 | `.diagnostics/week5-build.log` |
| OpenSpec全仓严格校验 | 29项通过，0失败 | `.diagnostics/week5-openspec.log` |
| `git diff --check` | 无空白错误 | `.diagnostics/week5-diff-check.log` |

APK位置：`mobile/build/app/outputs/flutter-apk/app-debug.apk`。安装命令：`adb -s emulator-5554 install -r mobile/build/app/outputs/flutter-apk/app-debug.apk`；启动：`adb -s emulator-5554 shell am start -n cn.pandora.pandora_mobile/.MainActivity`。设备周日语义快照明确为“10月18日 周日，11条记录”，消除了首次设备验收发现的漏记录。

首次扩展测试曾发现新增测试字段查找方式错误、旧入口断言失效与懒加载错误面板未滚动可见；均修正后回归。没有删除权限、正文内容或分页校验来使测试通过。OpenSpec既有`configure-project-workflow`同时声明`skip_specs`又含规格目录，本次移除冲突的`skip_specs`设置后全仓可校验。

页面测试加载项目标题字体与中文正文测试字体，避免字体缺失的方框被误当页面证据。原测试缺少 SharedPreferences 替身导致的草稿读取错误已修复，未屏蔽应用正常错误状态。

截图矩阵：390×844、320×844（1.5倍字体）、480×960，共33张页面截图。另有Android模拟器 `emulator-5554`（1344×2992px / 480dpi）ADB截图。设备验收为模拟器，未宣称实体手机已验收。

## 可复现手工步骤

1. 安装 Mock APK并启动，默认导图；检查四卡、有效标题、无灰色日期，点公司任务只出现列表。
2. 进入视图，查看月末可见、无下方重复当天列表；点击繁忙日期打开完整记录；切周检查七天与两条预览。
3. 日志→下属日志，组合姓名、部门、日期；检查不匹配为空且作者头像姓名可见。
4. 日志→右下加号；编辑已有当天日志，或选择无日志日期创建；保存草稿、重新进入、提交，再直接修改。进入详情发布评论并回复。
5. 详情中超过24h的本人日志显示灰色锁定按钮。自动化使用可注入时钟验证恰好24h及更晚拒绝，不依赖手工等待一天。
6. 我的→任务管理；全部任务包含下属记录，筛选/切换后可进入详情；返回我的仅保留人员展示索引，人员页可按部门筛选。

## 非功能验证

| 目标 | 方法与边界 |
| --- | --- |
| 易用性与屏幕适配 | 320/390/480dp截图与几何断言；1.5倍字号；360×640、412×915/1.5、800×1000遍历路由无布局异常；小屏任务筛选弹层能滚动至应用按钮；FAB与日期末行分开 |
| 数据范围与可靠性 | Mock递归下属/员工隔离、越权与无效正文拒绝；窗口边界/首次时间不变；空/断网/恢复状态；HTTP适配器模拟分页后403时清除旧成员数据。以上为前端/替身验证，非真实后端安全验收 |

## 后续与限制

- 真实服务端标签、参与人、评论、24h、分页、鉴权与持久化由后续联调验证；本批次不运行未改动的后端测试。
- 新柴犬素材重制与全应用素材覆盖不在最新九张问题图批次内，沿用现有登记素材；旧总体素材任务保持未完成，不能将旧小猪宣称为新素材。
- 原OpenSpec后端/Web/真实联调任务未勾选或归档；远程Issue关联、用户视觉验收与实体手机验收待后续。
- 恢复本轮改动时须按文件/代码块审阅；工作区有混合用户修改，禁止整体回退或清理。
