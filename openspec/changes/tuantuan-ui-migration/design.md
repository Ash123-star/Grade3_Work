# Design

## Architecture

- `mobile/lib/theme/app_theme.dart` 承载语义颜色、圆角、阴影和动效 token。
- `mobile/lib/shared/generated_assets.dart` 统一资源路径和素材组件。
- `mobile/lib/shared/paper_layout.dart` 提供卡片、分段控件、底部操作和背景纹理容器。
- 页面只组合公共组件和业务数据，不直接解析装饰图集坐标。
- 资源使用本地 `assets/generated_ui/`，不执行网络加载。

## Asset pipeline

用户提供的 `装饰性素材.png` 是 4×4 透明图集。按网格裁成 `decorations/` 下 16 个独立 PNG，保留原始图集和原始资源目录。

业务图标、角色、背景和参考板复制到 ASCII 文件名目录，pubspec 只声明 `assets/generated_ui/`。参考板仅用于视觉对照，不进入运行时页面。

## Visual migration

- 背景：纸张纹理低透明度铺底，页面内容使用暖白和语义浅色卡片。
- 导图：四象限保留，图标改为用户提供的彩色图标，欢迎区使用困团角色和少量装饰。
- 视图：保留日/周/月业务结构，记录和日期使用圆角、胶囊和浅色分区。
- 日志：记录卡、草稿提示和底部操作使用统一代码组件。
- 组件：卡片、弹窗、底部弹层、Toast 和图表由 Flutter 构建，图片不承担文字和交互。

## Risks

- 用户素材的内部文字/示意图可能只是参考板，不能作为真实数据。
- 透明图片在不同设备上的边缘需要截图检查。
- 现有工作区含混合用户改动，本批不回退、不提交、不推送。
