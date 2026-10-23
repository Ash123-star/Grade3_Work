# Why

月历记录条受高度和 FittedBox 双重压缩，字号难以阅读；现有同级内容和底部五栏只能点击切换。

# What Changes

- 月历扩展到页面安全区域全宽，记录采用不大于10dp的适宽紧凑字号、前6字单行，不显示省略号，每格最多5条；点日期查看全部。
- 仅月视图恢复右下角创建任务悬浮按钮，“今天”放在日周月导航栏下方靠右，保持既有派发权限。
- 底部五栏采用原生PageView随手指平移；日周月、任务分类、AI分析标签、成员面板分类保留同级平移切换。
- 修复日志页左滑误入下属日志：下属日志仅点击入口进入。
- 保留按钮和权限；内部切换优先，边界不循环，详情和编辑不接入横向导航。

# Capabilities

## New Capabilities
- `mobile-readable-calendar-navigation`: 月历可读预览及分层横滑导航。

## Modified Capabilities
- None.

# Impact

- Flutter 月历、路由、共享手势及上述页面；无 API、数据、数据库和依赖变化。
- P1，本地 Issue：`docs/issues/mobile-calendar-readability-swipes.md`；远程编号待关联。
