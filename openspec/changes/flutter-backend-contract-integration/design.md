# 设计

## 契约来源

以后端 `server/src/main/java/cn/workpanel/module/**/controller` 和实际 Controller 注解为唯一接口来源。已实现路径包括 `/api/auth`、`/api/tasks`、`/api/logs`、`/api/reviews`、`/api/dashboard`、`/api/organization`、`/api/notifications`、`/api/ai` 和 `/api/analytics`。

## 适配方式

`Repository` 接口继续服务页面层；`HttpRepository` 负责三件事：资源到后端路径和动词的映射、中文表单字段到后端 DTO 的转换、后端响应到 `Record/PageResult` 的归一化。真实请求失败直接转换为 `ApiFailure`，不回退到 Mock。

## Mock 开关

`USE_MOCK` 仍可显式设为 `true` 用于离线演示，默认值改为 `false`，因此普通运行优先访问真实后端。

## 已知缺口

- `feedback` 页面没有对应后端反馈 Controller，真实模式下写入会返回“不支持”。
- 组织管理部分页面的细分写操作依赖后端已有 revision 路由，当前页面字段仍需逐项确认 DTO 语义。
- 文件上传和 AI 流式任务尚未纳入通用 `Repository`，仍需独立的 multipart/SSE 数据源。
- 注册页面目前只能把“部门”文本直接作为 `departmentId`，正式使用需要接入 `/api/auth/departments` 选择器。
