## ADDED Requirements

### Requirement: Minimal code-drawn brand opening
开屏SHALL以前端绘制延续用户图标的明黄背景、白色角色、深灰粗线条，只显示应用名称。故事优先级P1，范围为进程启动展示，不改变业务页主题。

#### Scenario: Normal cold start
- **WHEN** App进程启动
- **THEN** 显示同风格角色与应用名称，角色轻微上移后交叉淡入原有登录、首页或会话恢复页面，不展示旧卡片和无关标语

#### Scenario: Constrained viewport or reduced motion
- **WHEN** 屏幕空间有限、系统文字放大或启用减少动态效果
- **THEN** 内容适配约束，标题不溢出；减少动态效果时保持角色静止并快速淡化

### Requirement: Startup state survives visual handoff
开屏MUST保留底层会话恢复和路由组件状态，MUST NOT因遮罩移除重新挂载底层页面；鉴权与错误处理沿用既有逻辑。

#### Scenario: Parallel recovery and animation
- **WHEN** 开屏播放并结束
- **THEN** 底层启动并行执行且组件位置稳定，结束后才允许底层交互与聚焦，不重复播放或重复启动恢复

#### Scenario: Recovery is slow or fails
- **WHEN** 动画结束时账号恢复仍未完成或失败
- **THEN** 显示既有加载或错误重试界面，不无限等待动画，不跳过身份确认

### Requirement: Native launch branding matches Flutter
Android原生启动SHALL使用配套黄底与静态矢量角色，不再引用旧开屏图片。

#### Scenario: Native launch to first Flutter frame
- **WHEN** Android冷启动进入Flutter开屏
- **THEN** 原生与Flutter采用同一背景色和角色风格，系统管理原生启动图形区域
