# 日周月视图与页面操作区改写验收

日期：2026-10-13；Windows / Flutter 3.38.7 / Dart 3.10.7。变更：`flutter-calendar-agenda`；本地 Issue：`docs/issues/flutter-calendar-agenda.md`。

## 实现
- 全页面共享骨架删除顶部页名；返回、消息、今天、建议草稿等操作置于内容滚动区。AI Mock 页面改用同一 PageBody，并保留原滚动控制器；正式 AI 页面已有 PageBody 自动接入。
- 日视图完整任务/日志列表，真实时间和详情入口；日志草稿编辑复用原权限、加密存储及版本路径。
- 按最新用户修正，周视图恢复纵向七日。每天最多两个 156dp 固定宽度胶囊，可用空间不足时收缩；不拉满页面，日期点击打开全量当天记录。
- 月历恢复圆角、无直线网格的布局，保留两条彩色预览、+N、当天列表。颜色集中定义，文字区分任务与日志。
- 当天弹层会话变化或失权时清除旧内容。后端/API/数据库无变更。

## 已验证
- `calendar_agenda_test.dart`：无页名、返回操作可用、操作随页面滚动消失且能返回、日列表→日志详情→编辑草稿、月格限量与弹层失权清除、加载/空/403/离线。
- `calendar_report_contract_test.dart`：完整分页与业务日期继承，周七行共用 x 坐标且 y 递增，无内部 Scrollable；胶囊宽度 156dp；点日显示全部记录。
- `calendar_agenda_visual_test.dart`：实际 Flutter 360dp（1.5 倍字号）和390dp渲染，日/周/月及AI操作滚出屏幕。10张截图位于 `docs/evidence/calendar-agenda/`，已查看周/月/AI滚动后截图。
- 三文件定向测试20项通过（固定宽度断言随后追加，纳入最终回归）。最终分析无问题/exit0；OpenSpec规划严格18/18/exit0。
- 两项非功能证据：易用性（窄屏大字号无渲染异常、胶囊限长与完整阅读入口）；安全（错误不回退样例、账号变更清除弹层内容、既有授权请求断言保留）。

## 统一回归
最终全量Mock与正式HTTP契约运行结果待写入。命令使用 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe D:/flutter/bin/cache/flutter_tools.snapshot --no-version-check`，后接 `analyze --no-pub` 或 `test --no-pub --concurrency=1 --dart-define=USE_MOCK=true/false --reporter expanded`。

首次回归6处旧页名断言失败，已改为实际正文、目标页面和对象ID检查，未削弱权限或请求断言。之后遇到Windows截图文件被映射锁定（errno1224）；保留失败日志，最终改串行运行以减少写入冲突。旧截图由原测试自动刷新；不将失败截图当验收证据。

## 未验证与阻塞
HTTP测试使用本地适配器，不能证明真实后端、数据库、Android设备或TalkBack通过。未构建APK。工作区已有上一批未提交接口缺口文档，遵守AGENTS混合改动规则，未提交、推送或创建PR。产品整体仍未完成验收。
