## 1. 布局实施

- [x] 1.1 改为横向图标标题栏及等高的两行两列视口布局，保留派发按钮空间和小屏兜底。
- [x] 1.2 内容区取消三条截断，使用剩余高度与块内滚动，保留查看全部和状态提示。
- [x] 1.3 更新产品基线及 mobile README 的首页布局说明。

## 2. 验证与归档

- [x] 2.1 运行 Flutter 静态检查和现有布局、UI 测试，构建并检查 Android 模拟器画面。
- [x] 2.2 运行 openspec.cmd validate --all --strict，确认完成后归档本变更。

验证记录：Flutter analyze 无问题；现有 18 项测试全部通过，包含小屏、大字体和平板布局；debug APK 构建成功并安装至 Android 模拟器；已检查导图截图 mobile/docs/screenshots/01-dashboard.png；OpenSpec 严格校验通过，主规范已同步并归档。
