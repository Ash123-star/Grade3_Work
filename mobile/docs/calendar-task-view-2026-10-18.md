# 2026-10-18 任务视图与月历验收记录

关联 OpenSpec：`frontend-requirements-adjustment`，tasks 5.7、5.8。优先级 P0。远程 Issue 编号待项目看板补录（原任务 1.1 仍未完成）。当前分支 HCJ；工作区混合既有修改，未提交或推送。

## 最新要求与实现范围

用户最新要求覆盖此前“任务和日志合并显示”“每天四条”“小屏允许滚动”的描述。

- 日、周、月视图仅订阅 `datedRecordsProvider('tasks')`；删除日志合并、类型图标分支和类型文案前缀。记录和日期弹层都打开任务详情。
- 日期位于单元格左上角。每个日期最多三条记录预览，额外记录及剩余数量不出现在网格中；点击日期仍可查看全部任务。
- 跨日任务按全月固定轨道分配，每周一条连续矩形色带，跨周续段保持同一轨道。只有实际开始日显示标题前四个字符，文字约束在开始日格内；其他日期仅显示标签颜色。
- 月历使用剩余视口高度均分周行，月视图无纵向列表或滚动回退。月视图的切换和今天按钮放在日期下方同一行；底部为新增按钮留出区域，避免遮挡月末。
- 年月标题保持单行，下拉打开年月日滚轮，取消不改变日期，确认后更新。
- 月查询覆盖首尾完整周；Mock 用开始至截止日期与查询范围重叠筛选任务，添加“数据结构实训”跨周演示任务。

所有任务继续经现有 Repository 获取；未修改真实 HTTP、服务端、数据库或权限规则。普通员工及有派发权限的用户沿用原入口权限。无任务显示空状态，任务请求失败可重试；日志数据或日志读取失败均不影响视图。

## 验证结果

环境：Windows / PowerShell，Flutter 3.38.7、Dart 3.10.7；SDK `D:\flutter`，缓存 `D:\FlutterPubCache`。以下最终检查均取得明确退出码 0。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 6 个定向测试文件 | 40 项通过 | `.diagnostics/calendar-tasks-tests-final.log` |
| `dart analyze` | No issues found | `.diagnostics/calendar-tasks-analyze-final.log` |
| Mock debug APK | assembleDebug 成功 | `.diagnostics/calendar-tasks-build.log` |
| `openspec.cmd validate --all --strict` | 29 项通过 | `.diagnostics/calendar-tasks-openspec-final.log` |
| `git diff --check` | 无空白错误 | `.diagnostics/calendar-tasks-diff-final.log` |

测试覆盖三视图只查询任务、类型文案移除、记录进入任务详情、加载/空/失败、跨月查询、三条容量、跨周同轨、标签颜色、标题四字符及宽度限制、日期滚轮取消/确认、日期弹层展示被隐藏记录、身份失效清除弹层数据。相关日志页、任务管理及路由回归一并通过。

初轮验证发现：月视图在小屏加载时沿用大型骨架会溢出；顶部三行控件与底部留白导致色带过小。修复为紧凑加载指示、两行控件和自适应周高。过期测试中的日志条数、重复标题查找及固定宽度断言也已按新行为修正，保留完整记录数与几何边界检查。

两项非功能验收：

1. 易用性与适配：2026 年 11 月六周月历在 320×640、360×640、390×844、480×960，以及 320×844 / 1.5 倍字号下全部可见；日期行、色带和月末均在视口内，拖动月历不改变位置。检查截图无日期与色带重叠。
2. 可靠性：日志读取故意抛出异常的测试替身下，日/周/月仍只请求任务并正常渲染；任务空/断网/无权限状态及弹层身份失效均有断言。此处为前端替身测试，不代表服务端安全验收。

## 截图

截图来自实际 Flutter Widget 渲染，已加载中文字体并逐张查看。文件位于 `mobile/docs/evidence/week5/`：

- `month-tasks-320x640-1.0.png`
- `month-tasks-360x640-1.0.png`
- `month-tasks-390x844-1.0.png`
- `month-tasks-480x960-1.0.png`
- `month-tasks-320x844-1.5.png`

截图中的绿色需求评审和棕色数据结构色带均跨周，分别保持第一、第二轨道；续段不重复标题。11 月 5 日有六条任务，网格只展示三条；11 月 30 日仍完整可见。旧 `week5-ui-adjustment.md` 中早期截图不能代替本次截图。

## 复现命令与手工步骤

在 `mobile/` 执行：

```powershell
$env:FLUTTER_ROOT='D:\flutter'
$env:PUB_CACHE='D:\FlutterPubCache'
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' analyze
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' 'D:\flutter\bin\cache\flutter_tools.snapshot' --suppress-analytics test --no-pub --dart-define=USE_MOCK=true test/calendar_agenda_test.dart test/calendar_agenda_visual_test.dart test/calendar_report_contract_test.dart test/week5_ui_acceptance_test.dart test/week5_mock_workflow_test.dart test/layout_test.dart --reporter expanded
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' 'D:\flutter\bin\cache\flutter_tools.snapshot' --suppress-analytics build apk --debug --no-pub --dart-define=USE_MOCK=true
```

根目录执行 `openspec.cmd validate --all --strict` 和 `git diff --check`。

安装 `mobile/build/app/outputs/flutter-apk/app-debug.apk` 后进入视图：分别切换日、周、月，确认只有任务；月视图查看跨周“数据结构实训”色带并点击日期看全部；打开年月下拉，取消后日期不变，重新选择并确认；检查六周月份及最末一行无需滑动。

## 未验证与限制

- `adb devices -l` 返回 `emulator-5554 unauthorized`，因此本次未执行模拟器安装与设备截图，不沿用此前设备验收结论。用户视觉确认、实体手机验收仍待完成。
- 真实后端的范围重叠查询、鉴权及持久化按用户要求留待后续联调；本次验收是 Flutter + Mock 范围。
- 原总体变更的其他后端、素材、Web、Issue 和真机任务保持未完成。
