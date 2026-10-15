# Why

当前 Flutter 工程的路由、页面、Mock 数据和状态集中在少数大文件中，后续接入真实后端时容易让页面直接依赖数据实现，也难以按业务域并行维护。需要在不改变现有演示契约的前提下建立清晰的应用分层。

# What Changes

- 增加 `routing` 和 `theme` 应用层目录。
- 将数据模型、Repository 和 Mock 实现按职责迁移到 `data/models` 与 `data/repositories`。
- 将现有页面按认证、导图、视图、日志、AI 地图、我的、任务、审核、通知、分析、设置和公共页面划分。
- 保留现有 Mock/HTTP Repository 接口，使页面只依赖稳定的数据访问边界。
- 保留现有五栏导航、演示数据和状态交互，后续再接入真实后端。

# Capabilities

### Modified Capabilities

- `flutter-architecture`: Flutter 应用按职责和业务域组织，路由、状态、主题和数据访问边界可独立替换。

# Impact

影响 `mobile/lib` 的目录和 import 路径，影响 Flutter 测试引用路径；不修改后端 API、数据库、真实认证或网络行为。
