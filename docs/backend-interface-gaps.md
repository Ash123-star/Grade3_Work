# Flutter 与后端接口缺口登记

> 2026-10-29补充：剩余接口代码接入状态以 docs/mobile-remaining-api-implementation-status.md 为准。用户已取消意见反馈，移动端入口/表单/Mock资源已删除，旧深链转帮助页；不新增feedback服务。任务评论/日志回复沿用现有真实接口，RETURNED、成果附件、团队目录、AI scope和确认version/幂等回执已接入源码，尚未统一验收。日志阅读登记已停用，不新增人员清单。下文保留的旧缺口或历史验证不能代表本批已通过。

> 2026-10-29状态更新：移动端六组P0接口与#17已补入服务端源码和V22迁移，当前为“已接入、未验证”。最新逐项矩阵见 [mobile-p0-implementation-status.md](mobile-p0-implementation-status.md)。以下为历史审计，旧“缺失/待实现”描述不能直接作为当前代码结论；未运行测试、编译、服务、迁移及运行时OpenAPI生成，P1与其他历史缺口不因本批实现自动关闭。

更新日期：2026-10-20（Asia/Shanghai）

2026-10-20 补充：移动端完整覆盖矩阵见 `mobile/docs/api-surface-coverage.md`。该矩阵区分已接入、字段待对齐、待定契约、本地/演示四种状态，作为后端围绕前端接口实现的输入；未定案路径不视为现有接口。

## 核对结论

本登记对照 Flutter `HttpRepository`/专用 AI 与通知数据源、Spring Boot Controller 映射和 `docs/openapi.json`。除“我的反馈”资源的通用映射可能触发未实现读取外，当前已启用正式主链路均映射到后端已有路径；明确未支持的写操作会在客户端拒绝或仅在 Mock 演示。产品要求仍有下列服务端接口或现有接口能力缺口，须后续由小组设计、分配并实现。

OpenAPI 快照包含下述现有路径，例如 `/api/ai/jobs/{id}/confirm-task`、`/api/logs/{id}/read`。缺口是新业务操作或契约能力，不应误报为这些已存在路径缺失。此登记不批准具体新 URL、DTO、数据库结构或状态迁移。

## 待完成项

| ID | 优先级 | 缺口类型 | 当前后端能力 | 后续工作与验收边界 |
|---|---|---|---|---|
| API-GAP-01 意见反馈 | 已取消 | 产品范围移除 | 2026-10-29用户明确不实现；删除移动端入口、表单和Mock支持，旧深链转帮助页 | 不新增feedback服务；最终验收覆盖旧链接和无请求。 |
| API-GAP-02 任务退回补充 | 源码接入未验证 | 既有后端与客户端已对齐 | POST /tasks/{id}/events，RETURNED，version/text；派发人或管理员在FEEDBACK退回RECEIVED，事件/审计/outbox原子 | 最终验收退回→重新反馈→验收、非法阶段、越权、旧版本、材料关联。 |
| API-GAP-03 日志阅读人员清单 | 产品停用 | 不新增 | 移动端已停用阅读登记；保留历史和兼容接口 | 不恢复入口、不新增清单；历史记录不作为本批待实现。 |
| API-GAP-04 AI范围筛选 | 源码接入未验证 | 已增加scope | SELF/AUTHORIZED，默认AUTHORIZED，服务端实时范围上限；后台/重试/来源分析保持 | 最终验收SELF隔离、失权、来源及后台一致性。 |
| API-GAP-05 AI确认版本原子保护 | 源码接入未验证 | 已增加version/行锁/回执 | version/actionIndex/task及Idempotency-Key；V23保存命令摘要/来源/原响应，与TASK_CREATE审核同事务 | 最终验收旧版本零写入、并发编辑、同键重放/异内容冲突及审核导航。 |
| API-GAP-06 任务字段与标签字典 | 源码已存在待统一验收 | 当前任务DTO/标签资源已经更新 | TaskDraftNormalizer接受participants/startAt/labelId，兼容ownerId/collaborators；Flutter映射tagId至labelId；task-labels查询/维护 | 旧文档的仅group/collaborators和硬编码标签结论已过时；最终验证实际HTTP字段/权限/审核和兼容性。 |
| API-GAP-07 已提交日志直接修改 | P0源码接入未验证 | PUT /logs/{id}/content | 本人24小时/首提时间/版本/历史/outbox；旧客户端update别名接入content | 最终验收时间边界、并发和旧候选失效，见P0实现记录。 |
| API-GAP-08 任务评论与回复 | 源码已存在待统一验收 | 现有任务/日志comments支持parentId | Flutter映射parentCommentId；任务评论必填幂等键、重复409；日志回复无幂等保证；同对象范围/父节点和通知 | 最终验收正常/错父节点/越权/重复；不把Mock当真实证据。 |

## 不属于缺失接口的已核对事项

- 日志显式登记已由 `POST /api/logs/{id}/read` 提供，客户端已接入；缺的是阅读人员清单读取。
- 任务成果反馈已由 `POST /api/tasks/{id}/events` 的 `FEEDBACK` 提供；缺的是派发者“退回补充”转换，不是员工成果反馈接口。
- AI 创建、草稿、SSE、取消、重试、用量、地图边和人工确认路径均已存在；范围选择和确认版本并发条件不足。
- 附件上传/下载、头像、组织、审核、统计导出、通知 SSE 和消息已读路径均在当前 Controller/OpenAPI 中找到。设备端文件选择/保存仍是客户端设备验收，不是后端缺接口。
- “我的反馈”无服务端读取/提交接口；Flutter 正式模式的未知 resource 已显式失败，不再把 `/feedback` 或 `/feedback/{id}` 当作约定路径。Mock 演示行为不能作为服务端能力证据。
- 当前任务表单与后端任务白名单字段不一致（API-GAP-06），因此 HTTP 路径存在也不能视作任务新建已完成真实接入。

## 开发与分工约束

以上每个缺口进入实现前，应分别创建或关联 Issue，并建立覆盖后端、OpenAPI 快照、Flutter 调用、权限、迁移（如需要）、集成测试和部署说明的 OpenSpec change。设计阶段须比较至少两种可行契约路线，确定角色范围、状态迁移、字段、错误、幂等、并发和回滚后，再分配后端与客户端负责人。接口定案前，Flutter 不得调用推测路径；数据库变化只新增 `server` Flyway 迁移。统一覆盖与显式路由修复关联 `mobile-api-surface-contracts`。

关联跟踪：`openspec/changes/flutter-stage3-layout-rebuild/tasks.md` 3.6、`openspec/changes/flutter-backend-contract-integration/tasks.md` 2.1，以及本地 Issue `docs/issues/flutter-backend-interface-gaps.md`。
