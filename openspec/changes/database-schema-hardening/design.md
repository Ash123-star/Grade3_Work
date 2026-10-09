# Design

## Context

后端实际使用 `server/src/main/resources/db/migration` 的三段 Flyway 迁移。现有表已经覆盖组织、任务、日志、审核、通知和 AI，但 `reporting_relations`、`review_steps` 和日报中的 `taskIds` 仍有完整性依赖服务层的问题。

## Goals / Non-Goals

**Goals:**

- 让数据库直接拒绝跨公司日报任务关联、汇报环和审核自审。
- 保持现有 Java 查询和 REST 请求兼容。
- 用追加式 Flyway 迁移完成增强，并提供可读字段字典。

**Non-Goals:**

- 不重命名现有表和字段。
- 不把两套数据库模型合并到同一迁移链。
- 不把业务权限判断完全下沉到 PostgreSQL；服务层仍负责数据范围和操作权限。

## Decisions

1. 新增 `log_tasks` 作为日报任务关系的结构化事实来源，同时保留日报 JSON 以兼容现有客户端。保存草稿和审核生效时同步关系表。
2. 在 `reporting_relations` 上使用公司行锁加递归查询触发器，既防止直接 SQL 写入形成环，也串行化同公司并发关系修改。
3. 在 `review_steps` 保存 `applicant_id`，通过复合外键和 `CHECK (reviewer_id <> applicant_id)` 让数据库直接阻止自审步骤。
4. 使用新迁移 `V4__business_integrity.sql`，不修改已应用的 V1-V3。迁移先回填现有日报关系，发现无效 ID 时整体失败。
5. 约束只固化稳定业务事实；角色范围、审核路由和对象可见性继续由应用服务检查。

## Risks / Trade-offs

- [Risk] 既保留 JSON 又增加关系表，短期存在双写一致性风险 → 所有日报正文写入集中调用同步方法，并增加集成测试。
- [Risk] 旧数据包含无效 `taskIds` 时迁移会失败 → 迁移前提供 SQL 检查，失败时事务整体回滚，不产生半成品。
- [Risk] 触发器增加组织关系写入成本 → 关系修改频率低，且按公司锁定，优先保证正确性。

## Migration Plan

1. 先在隔离数据库执行 V4，验证回填、环保护和自审约束。
2. 部署包含同步逻辑的后端版本，再允许写入日报和审核数据。
3. 回滚应用时保留 V4；旧应用仍可读 JSON，但必须先停止产生新审核步骤，避免旧代码无法提供 `applicant_id`。
