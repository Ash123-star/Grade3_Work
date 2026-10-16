## Why

成员 B 负责认证、组织和审核后端。当前模块已有运行路径，但 Controller 中仍混有 SQL 和业务规则，应用接口未全部接入，登录失败锁定及完整权限、并发验收证据不足。按用户确认，以 MVP 分工确定本阶段交付范围，PRD 用作参考；结合课程要求、现有 Flyway 模型与实际实现形成可分批交付的闭环。

优先级：MVP。负责人：B（刘逸冰）。Issue：认证 #3、组织 #4、审核 #5（Ash123-star/Grade3_Work）；Sprint 编号待关联。用户指定在 `lyb` 分支实施。

## What Changes

- 一起规划认证、组织、审核，再按认证 → 组织 → 审核顺序实施；用户已授权依次交付三批。
- 补齐注册待确认、首次改密、登录失败防护、会话注销与实时状态检查；保留现有 API 的兼容行为。
- 将 B 模块的业务规则、事务与数据库访问移出 Controller，并补齐组织完整性、独立审核、版本冲突和审计验收。
- 按用户指定的 MVP 优先口径，保留主规格的分层复核、组织范围和版本冲突策略；PRD 的同对象单条待审、禁止同级访问和团队长禁止审核不纳入本批新增约束，差异记录在设计中。
- 建立单元、真实 PostgreSQL/Redis 集成、安全和性能证据，以及接口、迁移、贡献与 PR 追溯。

范围：auth、organization、review 及其测试、新增 Flyway 迁移和配套文档；对应 PRD US01–06、US27–28，协作 US14/16 的审核部分。非目标：Flutter 页面、任务/日志业务实现、通知/AI、公司多租户开户、公共安全设施重写。

验收目标：注册 → 登录 → 独立归属确认 → 组织权限生效 → 候选修改 → 独立审核 → 新版本生效可演示；正常、无效输入、越权、自审、并发冲突均有运行证据。安全与性能分别记录，未测项目保持未完成。

## Capabilities

### New Capabilities

无。复用现有后端能力，避免重复规格。

### Modified Capabilities

- `collaboration-backend`: 细化认证与组织范围、候选版本与独立审核，增加登录失败防护、组织完整性及成员 B 交付验收要求。

## Impact

- 预计涉及 `server/src/main/java/cn/workpanel/module/{auth,organization,review}`、对应测试、`server/src/main/resources/db/migration` 和后端文档。
- 公共 Security、Actor、Db、Business、OpenApi 由 E 协调；任务/日志变更应用由 C 协调，事务 outbox/通知由 D 协调，客户端由 A/E 联调。
- 保留现有 PostgreSQL 会话和候选版本模型；登录防护可能新增 Flyway 迁移，不修改已发布迁移。契约变化与 E 同步 SpringDoc、接口文档和 OpenAPI 快照。
- 与 `initial-product` 2.1–2.4、`architecture-modularization`、`api-contract-unification` 和 `database-schema-hardening` 建立任务映射，不重复勾选已有任务。
- 当前回归 10 项中 9 项通过、1 项任务转交失败；C/E 测试夹具与范围规则核对列为最终回归依赖。规划完成不代表功能完成，不触发功能提交、推送或归档。
