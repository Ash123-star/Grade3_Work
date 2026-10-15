# 设计

路由实现继续使用现有 `go_router` 和 `StatefulShellRoute.indexedStack`。主导航分支分别为 `/dashboard`、`/view`、`/logs`、`/ai`、`/me`，认证和系统状态使用栈路由。`/me/team/:memberId/:category` 暂时复用现有成员详情承载页，分类视觉和数据分区留给后续页面设计阶段。

管理者从“我的”进入下属工作台；日志页继续保留下属日志入口，以满足产品规则。路由守卫仍由会话状态控制，服务端权限是最终授权来源。
