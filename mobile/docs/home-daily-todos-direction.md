# 首页每日事项设计方向（待实施）

2026-11-04。关联 `openspec/changes/home-company-daily-todos/`，本文件及原型只用于布局与交互评审，未接入Flutter或真实服务。

## 选定的提案方向

参考仓库现有团团首页 `docs/evidence/week5/device-dashboard.png` 和 Material 3 语义角色，保持暖白纸面、浅蓝事件纪、浅杏任务看板、薄荷绿主要操作。图标直接引用现有 `assets/generated_ui/icons/`，未新增第三方素材；素材许可证与来源继续沿用现有仓库记录。

把高大的四象限改成两张紧凑摘要，每张两条预览和查看全部；下方为全宽个人月历与选中日事项清单。标题不塞进日历格，格内只显示日期、未完成数与已完成标记，长内容在下方换行。事项完成操作与任务派发入口在视觉和文案上分离。导航更名为首页、公司、日志、AI地图、我的。

未选方案：继续四象限会挤占月历；手机侧栏/三列看板无法容纳长中文；在每个日期格堆叠todo标题会影响七列可读性。无需新UI框架或整体换肤。

## 原型

- 文件：`../prototypes/home-daily-todos.html`，浏览器直接打开，无构建或网络依赖，图标相对引用仓库文件。
- 顶部折叠的“交互原型”工具可切换正常、空态、加载失败、加载中、冲突、大字体与派发资格展示。
- 支持切月/跨年、选日、返回今天、新增/编辑日期与内容、完成/恢复、确认删除、查看两类完整示例列表。
- 所有数据为内存演示，刷新还原；模拟日期固定2026-11-04，绝不表示数据已云端保存。
- 公司/日志/AI地图/我的只提示正式产品将保留原页面，不制作虚假的业务链路。

## 验证范围与结果

Windows + 本机Edge headless + bundled Playwright：`node output/verify-home-prototype.cjs` 退出0。

- 320/360/390/480px × 标准/1.5倍字体共8组无横向页面溢出，已生成截图。
- 新增、完成、跨年改日期、确认删除、切月/回到今天、错误重试、冲突保留输入、加载/空态、隐藏派发入口和12项完整任务演示列表断言通过。
- JS页面异常0、损坏图标0。人工检查390px标准、320px大字体截图，页面可纵向滚动，长标题和卡片正常换行。
- 临时QA脚本、截图与JSON结果在忽略目录 `output/home-prototype/`（脚本为 `output/verify-home-prototype.cjs`）。它们仅证明HTML原型，不证明Flutter布局、TalkBack、服务端权限或生产可用性。

Flutter实施时将色彩/间距放回现有ColorScheme及ThemeExtension；主要按钮48dp，七列日期格使用整格触控并提供辅助选日。真实设备、系统字号、TalkBack、键盘及网络矩阵保持在OpenSpec未完成任务中。

## 实施补充

Flutter已按此方向实现，使用现有ColorScheme、PaperLayoutTokens及团团素材。真实组件截图见 [home-daily-todos.png](screenshots/home-daily-todos.png)，由合成数据的测试宿主渲染，宿主不包含正式底栏。四种宽度×两档字号的首页与编辑器测试已通过，真实HTTP/数据库链路也已通过；设备验收及整库回归限制见 [verification.md](../../openspec/changes/home-company-daily-todos/verification.md)。
