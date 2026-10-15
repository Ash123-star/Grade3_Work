## 1. 统一列表布局

- [x] 1.1 四个导图入口列表统一页面边距，记录卡片撑满可用宽度，统一说明样式并去除空状态行。
- [x] 1.2 更新产品基线及页面说明。

## 2. 验证和归档

- [x] 2.1 完成 Flutter 静态检查、现有布局和 UI 测试，构建 APK 并在模拟器检查四个列表画面。
- [x] 2.2 通过 openspec.cmd validate --all --strict 后同步规范并归档。

验证记录：Flutter analyze 无问题；layout_test.dart 与 demo_ui_test.dart 共 6 项测试通过（360×640、412×915 且字体 1.5 倍、800×1000）；debug APK 构建成功。显式 USE_MOCK=true 的演示 APK 已安装至模拟器，四个入口截图均确认卡片与搜索框左右对齐，截图见 mobile/docs/screenshots/06-company-list.png 至 09-log-list.png。OpenSpec 严格校验通过，主规范已同步并归档。
