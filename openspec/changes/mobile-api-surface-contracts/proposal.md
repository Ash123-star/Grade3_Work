# Why

Flutter 页面已经跨认证、组织、任务、日志、审核、统计、消息、附件和 AI 等模块调用后端。现有资料散落在 Repository、API_CONTRACT、OpenAPI 和缺口登记中；部分 UI 操作只有 Mock 行为，另有资源字符串会自动拼出未登记 URL，后端团队难以据以前端稳定边界为准实现。

# What Changes

- 建立完整的 Flutter 页面/操作/API 覆盖清单，标明前端期望契约、当前服务端实现、权限责任和验证状态。
- 固定当前已发布 REST/SSE 路径；未知资源在客户端适配层显式拒绝，不再推导 URL。
- 将缺少的功能登记为具名前端操作与待评审契约，不把 Mock 能力写成已接通，也不臆造服务器已经存在的路径。
- 对照 Flutter 请求 DTO 与服务端/OpenAPI 揭示不一致字段，作为后端实现的明确输入。

# Capabilities

## New Capabilities
- `mobile-api-surface`: Flutter 页面能力、前端操作和企业服务契约之间的完整映射及缺口状态。

## Modified Capabilities
- None.

# Impact

- Flutter：`mobile/lib/data/repositories/repository.dart` 的资源路由解析与已提交日志操作保护。
- 文档：`mobile/docs/API_CONTRACT.md` 与新增覆盖清单。
- 跟踪：新增 OpenSpec change；同步 `docs/backend-interface-gaps.md`。
- 后端、数据库、运行时 OpenAPI：本批不改；具体新增业务契约须后端负责人评审并实现。
- 优先级：P1。远程 Issue/Sprint 待关联，不编造编号。
- 负责人：前端 A/E 与对应后端模块负责人；本地 Issue 待建立。

# Acceptance Goals

- 所有当前路由可见的页面操作均能在覆盖表中找到已接入、仅本地、演示专属或待契约状态。
- 未登记资源不会产生 HTTP 请求；已提交日志修改不会调用草稿保存接口。
- 严格 OpenSpec 校验、受影响 Dart 静态检查和契约测试通过；测试结果能证明未知资源被拒绝。
- 不把文档/Mock/静态检查单独作为功能接通证据。
