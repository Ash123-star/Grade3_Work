## Why

当前项目只有产品方案和 OpenSpec 规划，没有可运行的 Android 前端骨架。后续服务端接口、权限和业务模块尚未全部就绪，如果先做零散页面，容易造成导航、视觉语言和页面状态不一致，也难以在早期进行产品评审。现在需要先建立一个可运行的 Flutter Android 前端框架，把方案中的五个主导航和核心页面完整呈现出来，接口位置统一预留，后续接入真实服务时不需要推翻页面结构。

## What Changes

- 新增 Flutter Android 应用工程及基础目录，配置 Material 3、Riverpod、go_router、Dio 和本地草稿存储依赖。
- 实现“我的｜AI 地图｜日志｜视图｜导图”五栏导航，默认路由进入导图。
- 实现导图四象限、个人面板、AI 地图、日志与下属日志、日/周/月视图、任务派发、审批、消息和设置等页面的可交互静态框架。
- 引入卡通风格 UI 资源和 OpenMoji 本地素材适配层，统一颜色、圆角、插图、空状态、加载状态和错误状态。
- 为认证、组织、仪表盘、任务、日志、审核、通知、分析和 AI 地图建立 API client、模型和 repository 接口；本阶段使用 mock 数据，不声称已接通后端。
- 为权限范围、派发资格、只读公司卡片、个人备注和 AI 建议确认预留状态边界，避免仅靠隐藏按钮表达权限。
- 添加运行说明、素材署名说明和前端验收任务。

## Capabilities

### New Capabilities

- `flutter-android-shell`: Flutter Android 应用工程、五栏导航、全页面路由、页面状态和可交互 UI 框架。
- `cartoon-ui-kit`: 轻松可爱的卡通视觉令牌、组件、状态插图和 OpenMoji 本地资产适配。
- `frontend-api-contracts`: 面向认证、组织、导图、任务、日志、审核、通知、分析和 AI 地图的客户端接口抽象与 mock 实现。

### Modified Capabilities

- 无。现有服务端能力尚未实现，本变更只提供客户端框架和接口契约，不改变后端业务要求。

## Impact

- 新增 `mobile/` Flutter 工程及 Android 构建配置、资源和测试目录。
- 后续服务端需要按客户端 repository 的请求模型和错误模型提供 REST API；本阶段不要求启动服务端。
- 新增 OpenMoji 资产清单和 CC BY-SA 4.0 署名文件；素材采用本地资源，不使用外部热链。
- 需要安装 Flutter SDK、Android SDK，并可执行 `flutter analyze`、`flutter test` 和 APK debug 构建。

