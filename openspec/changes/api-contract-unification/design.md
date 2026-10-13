# 设计

## 契约来源

SpringDoc 运行时生成的 `/api/openapi` 与 Controller 是实现事实；`docs/openapi.json` 为可提交的快照，`docs/backend-interface.md` 为面向联调人员的解释文档。三者必须使用相同路径、方法、请求字段、枚举和错误语义。

## 任务事件

事件类型统一为 `RECEIVED`、`FEEDBACK`、`ACCEPTED`、`TRANSFERRED`、`RESCHEDULED`、`ARCHIVED`、`WITHDRAWN`。转派要求 `ownerId`，改期要求 `deadline`，反馈和撤回要求 `text`。所有事件携带当前 `version`，服务端使用乐观锁。

## 非目标

- 不迁移既有 URL。
- 不修改已发布 Flyway 迁移。
- 不在本变更中拆分数据库模型或更换序列化框架。

## 验收

- OpenAPI、接口文档和 Controller 均列出 64 个既有操作及新增事件字段。
- 转派、改期的合法和非法请求分别有测试覆盖。
- `mvn test`、后端集成测试脚本和 `openspec.cmd validate --all --strict` 通过。
