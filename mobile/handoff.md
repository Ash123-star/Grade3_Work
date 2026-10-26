# Mobile 阶段交接

更新日期：2026-10-24（Asia/Shanghai）
范围：`mobile-page-experience-refresh`，只覆盖移动端实现与当前验收状态。本文用于新会话接续，不代表阶段交付或验收通过。

## 当前结论

- 用户 #1–#17 的移动端页面、交互、Mock 与 HTTP 适配均已接入；按点实施记录见 [`openspec/changes/mobile-page-experience-refresh/tasks.md`](../openspec/changes/mobile-page-experience-refresh/tasks.md)。这表示代码路径已建立，不表示每项已经验收。
- 2026-10-24 本次验收：`openspec.cmd validate --all --strict` 38 项通过、0 项失败，退出码 0；`D:\flutter\bin\flutter.bat analyze --no-pub` 无问题，退出码 0；Mock release APK 构建退出码 0。
- 完整 `flutter test --no-pub` 已运行结束：267 项通过、31 项失败、2 项跳过，退出码 1。失败覆盖 AI 工作台、Demo/路由、日志流程、月历、下属工作台和 HTTP 契约测试；明细见 [`openspec/changes/mobile-page-experience-refresh/verification.md`](../openspec/changes/mobile-page-experience-refresh/verification.md)。所有功能验收 task 仍未勾选。
- 月历定向测试确认 Mock 月查询包含 `t6`，但 UI 未渲染所期待的跨周片段（`calendar_agenda_test.dart:310`）；缺陷定位在数据读取之后，具体轨道/布局原因尚未确定。
- APK 已构建但未安装或手工操作。360/390/412dp 真机/模拟器验收、滚动帧性能、TalkBack/减少动画证据仍缺；正式服务端契约也未联调。不能宣称本阶段已完成。

## 已接入的核心工作

- **月视图 #1–#3**：`+N` 溢出计数、跨周续段标题、连续纵向月份流及跨月查询适配已接入。定向验收未通过：拥挤月份测试中 `t6` 已由 Mock 查询返回，但 `month-span` 未渲染；当前断言在 2026-10-12 周片段处失败，尚未证明 2026-10-19 续段。
- **任务表 #4–#5**：新表格页、固定字段行、横向列浏览/筛选及视图页入口已接入；“我的”旧入口移除，旧路由保留。测试需引用 `task_management_table.dart` 中当前路由使用的组件。
- **日志 #6–#8**：单字段底部编辑层、自动本地草稿、提交、24 小时编辑窗口适配、精简详情及移除阅读登记已接入。卸载时草稿保存曾访问已失效的 Riverpod `ref`，已改为缓存 `DraftStore`；待复验。
- **我的 #9–#11**：原地编辑个人资料与头像、扩展统计图和钻取/筛选契约、审批页奶油白布局已接入。
- **下属 #12**：员工资料头卡、日志提交状态月历及复用主月历的任务视图已接入。
- **导图/全局/审核 #13–#17**：公司任务派发时间排序、公司重点只读居中卡、个人重点独立编辑卡、清除业务演示文案（保留设置中的演示控制）、直属单级审核与创始人 Mock 免审适配已接入。

## 验收修复进度

- 当前完整测试有 31 项失败（不是交接前记录的 38 项）；除月历续段外，还包括 AI 输入/发送状态、旧 Demo UI 入口/表单假设、日志工作流、成员资料字段、任务表入口和日志 HTTP 契约等断言。逐项修复前应核对变更后的产品路径，不能用改弱需求的方式让测试变绿。
- `flutter analyze --no-pub` 已在当前工作区通过；Mock release APK 已成功构建，但 Flutter 提示找不到 CupertinoIcons 字体族，仅找到 MaterialIcons，需确认产品实际界面图标与打包字体。
- `flutter pub get` 因访问 `github.com/flutter/goldens.git` 网络超时失败；验收命令使用 `--no-pub` 复用现有依赖。Android APK 已构建但未安装或手工验收。服务端时间强制、组织权限、统计历史聚合、完整成员日志日历和正式单级审核事务均未验证。

## 下一步顺序

1. 按 `verification.md` 处理 31 项失败，从当前代码路径与断言逐一确认属于产品缺陷、过期测试还是夹具问题；优先隔离月历容量、AI 输入保留、日志创建/重试及入口迁移链路，始终保留原需求。
2. 每批修正后执行对应测试，再按计划重新统一运行测试、分析、Mock APK 构建和 OpenSpec strict 校验，记录明确退出码。
3. 安装 Mock APK 后按 `requirements-audit.md` 执行 360/390/412dp、1.5 倍字号、月历切换/跨月、表格双轴、日志键盘与草稿、图表交互、弹卡及权限变化；记录截图、滚动帧性能和无障碍证据。
4. 真实服务端契约、设备验收和逐项验收报告完成前保持所有功能任务未勾选。远程 Issue、分支推送和 PR 尚未完成；工作区仍混有服务端与其他移动端改动，本阶段不得提交或推送这些混合差异。

## 约束与入口

- 用户限定只修改移动端；服务端冲突记录为契约缺口，不能通过更改移动端弱化用户需求，也不修改服务端代码。本阶段后端待补契约见 [`mobile/docs/backend-contract-gaps-mobile-page-experience-refresh.md`](docs/backend-contract-gaps-mobile-page-experience-refresh.md)。
- 保持奶油白/团团主题，只使用现有 `app_theme.dart` 主题角色；新交互使用项目主题化组件，避免直接使用不符合现有视觉的 Flutter 成品控件。
- 每次实现只对应一个原始编号；所有实现完成后集中统一验收。具体细项、依赖和未勾状态以 OpenSpec 为准。
- 当前分支为 `HCJ`。工作区含大量移动端阶段改动，也含未提交的服务端 `TaskQueryService.java`、`TaskController.java` 与接口文档改动；不清理、不覆盖、不把它们当成已审核的正式服务端契约。
- 新会话先读本文件、上述 OpenSpec change 的 `proposal.md` / `design.md` / `requirements-audit.md` / `tasks.md`，再检查 `git status` 和相关移动端实现。后端接手者先读后端契约缺口文档，并与当前 `docs/backend-interface.md`、`docs/openapi.json` 及真实服务端实现核对。
