# AI 地图首页精简验收

## 2026-10-21 底部操作追加验收

用户确认删除整张欢迎卡和空结果说明，开始分析改为 PageFrame.bottom 固定操作，位于五栏导航上方。正式与演示页面均已更新；按钮不随正文滚动，生成中的禁用和取消/重试沿用原流程。

- `flutter analyze --no-pub`：退出码 0，无问题。
- `flutter test --no-pub --dart-define=USE_MOCK=true --dart-define=SCREENSHOT_OUTPUT=../output/ai-bottom-layout test/ai_map_ui_test.dart test/ai_http_workflow_test.dart`：21 项通过，退出码 0，覆盖演示页、正式 HTTP 工作流、失败恢复、权限和 360dp/1.5 倍字体；断言按钮位于 Tab 下方及五栏导航上方。
- `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`：退出码 0；adb 安装返回 Success。
- OpenSpec strict：28 项通过；git diff --check：退出码 0。
- 模拟器已打开新版 AI 页，UI 层级仅含三个分析 Tab、底部开始分析及五栏导航；截图 `output/ai-bottom-layout/emulator-ai-bottom.png`。已有结果的大字体截图 `output/ai-bottom-layout/34-ai-priority.png`。

未主动调用付费模型；无关锁文件与远程交付阻塞沿用下述记录。本条覆盖下述上一批卡片→按钮→Tab 的布局结论。

日期：2026-10-20。分支：`chore/ai-map-layout`。关联本地 Issue：`docs/issues/ai-map-layout-simplification.md`；OpenSpec：`tuantuan-ui-migration` 7.1–7.4。

## 实现结果

正式与演示首页按“把下一步想清楚”卡片→开始分析→发展分析/堵点风险/行动规划→结果排列。未生成结果时三个 Tab 仍保留。顶部大脑、建议草稿、用量、刷新工具、范围、日期周期筛选、优先三件事、关系图入口和来源范围说明已移除。正式生成仍使用既有当天/day 默认值，建议详情从行动规划进入，人工确认、来源阅读、失败恢复、取消和权限校验沿用既有链路。演示开始分析只刷新标明的演示数据。

PillTabs 新增默认关闭的 wrapLabels 参数，仅 AI 首页开启，窄屏大字可完整换行。未修改后端接口或数据库。

## 验证命令与结果

- `openspec.cmd validate --all --strict`：实施前 28 项通过；最终结果见本批终端输出。
- `D:/flutter/bin/flutter.bat analyze --no-pub`：退出码 0，无问题。
- 在 mobile 下执行 `flutter test --no-pub --dart-define=USE_MOCK=true --dart-define=SCREENSHOT_OUTPUT=../output/ai-map-layout test/ai_map_ui_test.dart test/ai_http_workflow_test.dart test/sunny_design_system_test.dart`：29 项通过，退出码 0。
- 在 mobile 下执行 `flutter test --no-pub --dart-define=USE_MOCK=false --dart-define=SCREENSHOT_OUTPUT=../output/ai-map-layout-formal test/ai_http_workflow_test.dart`：19 项通过，退出码 0；HTTP Adapter 受控响应，不能称为真实 DeepSeek 验收。
- 在 mobile 下执行 `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8080/api`：退出码 0；`adb install -r` 返回 Success，模拟器已进入新版 AI 首页。
- `git diff --check`：最终记录见本批终端输出。

非功能验收：360dp、1.5 倍字体截图与滚动未出现布局异常，完整 Tab 文字可换行；403 失权、取消、账号切换、503/预算失败及旧结果保留由既有工作流测试验证。截图位于忽略目录 `output/ai-map-layout/` 和 `output/ai-map-layout-formal/`，模拟器截图为 `output/ai-map-layout/emulator-ai-map.png`。

## 环境与限制

Windows、Flutter SDK `D:/flutter`、Android App_Run_API37 x86_64 模拟器；真实模式保留已有登录会话。实际模拟器已核对欢迎卡、按钮、三个 Tab 与删除项；本批未主动运行付费模型分析，未做真机/TalkBack 验收。

首次分析发现删去仍被来源弹层使用的字体 import，恢复后通过。Android 首次构建遇到 SQLite 官方下载超时，使用仓库 prepare-flutter-sqlite.ps1 校验官方二进制并预热缓存；随后发现旧 objective_c/SQLite hook JSON 包含 NUL，相关损坏缓存已移到忽略输出目录备份，再构建成功，未改依赖或业务数据。

交付限制：开始前已有 `mobile/pubspec.lock` 和 `mobile/packages/cute_ui/pubspec.lock` 的无关修改，按 AGENTS.md 第 4 节混合改动规则停止自动提交/推送；GitHub CLI auth status 确认未登录。代码与文档保留本地，未创建远程 Issue/PR，不报告远程交付完成。
