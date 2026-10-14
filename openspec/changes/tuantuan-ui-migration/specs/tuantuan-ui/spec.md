## ADDED Requirements

### Requirement: Local tuantuan visual assets

客户端 SHALL 从本地 `assets/generated_ui/` 加载用户提供的角色、业务图标、背景和裁剪后的装饰素材，禁止运行时请求外部图片。

#### Scenario: Offline asset loading

- **WHEN** 用户打开导图、视图或日志页面且设备无网络
- **THEN** 页面仍能加载角色、图标、背景和装饰素材，业务请求失败时只显示真实错误状态

### Requirement: Code-rendered interactive components

卡片、弹窗、底部弹层、Toast 和图表 SHALL 由 Flutter 代码渲染，图片只能作为视觉参考或插画内容。

#### Scenario: Accessible component states

- **WHEN** 用户使用大字体、TalkBack、加载、失败、成功或无权限状态
- **THEN** 组件保留真实文字、语义、操作和恢复路径，不依赖图片中的占位文字

### Requirement: Tuantuan page hierarchy

导图、视图、日志和我的页面 SHALL 使用统一的奶油纸张背景、圆角卡片、彩色图标托盘、角色状态和轻量装饰，同时保留既有导航、接口和权限规则。

#### Scenario: Narrow screen and large text

- **WHEN** 屏幕宽度为 360dp 或字体缩放为 1.5 倍
- **THEN** 页面不横向溢出，核心标题和操作可读，装饰不覆盖业务内容
