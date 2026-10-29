# 后端接口补充契约：移动端页面体验阶段

> 2026-10-29补充：剩余接口代码接入状态以 docs/mobile-remaining-api-implementation-status.md 为准。用户已取消意见反馈，移动端入口/表单/Mock资源已删除，旧深链转帮助页；不新增feedback服务。任务评论/日志回复沿用现有真实接口，RETURNED、成果附件、团队目录、AI scope和确认version/幂等回执已接入源码，尚未统一验收。日志阅读登记已停用，不新增人员清单。下文保留的旧缺口或历史验证不能代表本批已通过。

> 2026-10-29状态更新：六组P0接口与#17已有服务端源码及V22迁移，尚未执行测试、编译、迁移或HTTP联调。最新契约/源码矩阵和统一验收待办见 [mobile-p0-implementation-status.md](../../docs/mobile-p0-implementation-status.md)。下文保留2026-10-25审计背景，不能把旧“缺失”直接当作当前结论，也不能把代码接入视为验收通过；P1评论、退回和反馈不在本批接口范围。

更新日期：2026-10-25
关联 OpenSpec：[`mobile-page-experience-refresh`](../../openspec/changes/mobile-page-experience-refresh/)
用途：交给后端后续实现与更新正式 API 文档；本文只记录移动端依赖和当前缺口，不表示服务端已经支持。

## 2026-10-25 移动端与服务端接口审计结论

本次审计只读取并对比 `mobile/lib/data`、移动端页面调用点、服务端 Controller/应用服务和现有接口文档，未修改 `server/`。以下“缺失”表示移动端已经有真实 HTTP 映射或正式页面流程，但当前服务端没有可直接替换 Mock 的完整 REST 契约；“不匹配”表示路由存在，但参数、响应字段或过滤语义不足。

| 移动端服务 | 移动端调用 | 当前服务端情况 | 结论与后端待办 |
| --- | --- | --- | --- |
| 导图接收任务卡片 | `GET /tasks/received-card?cursor&limit` | `TaskController` 没有该路由 | **缺失**：新增分页接口，返回 `id/title/version/dispatchAt/phase` 及卡片所需字段，按当前用户可见接收历史排序，区分撤回、验收、归档 |
| 任务月视图/成员任务日历 | `GET /tasks?from&to&ownerId` | 当前列表只声明 `date/period/participantId`；工作区已有未提交任务区间查询改动尚未形成正式契约 | **不匹配**：正式支持 `from` 左闭、`to` 右开、`ownerId`，并在服务端执行跨界任务相交和组织范围校验 |
| 成员日志月状态 | `GET /logs/subordinates/calendar?ownerId&month` | 当前 `LogController` 没有该路由 | **缺失**：新增月状态接口，返回 `SUBMITTED/MISSING/FUTURE/UNKNOWN` 和真实入职日期；禁止客户端根据空列表推导缺交 |
| 日志列表日期范围 | `GET /logs`、`GET /logs/subordinates` 携带 `from&to` | Controller 当前只声明 `date/period` | **不匹配**：补充 ISO 时间范围参数并统一上海业务日边界，保留下属权限、部门和搜索过滤 |
| 提交后 24 小时日志直接编辑 | `PUT /logs/{id}/content` `{work,version}` | 当前只有草稿保存和审核修订路由 | **缺失**：服务端原子校验作者、submitted_at+24h、version，保留首次提交时间并记录历史；过期/越权/旧版本返回可区分错误 |
| 多维统计汇总 | `GET /analytics?date&period&groupBy&departmentId&teamId&ownerId` | 当前统计 Controller 只正式处理 `date&period` | **不匹配**：服务端需按同一授权范围执行维度和组织过滤，返回派发、接收、反馈、验收、逾期、日报提交的分子/分母及趋势桶 |
| 统计图表钻取 | `GET /analytics/details?...&metric&groupId&bucket&cursor&limit` | 当前没有 `/analytics/details` Controller 路由 | **缺失**：新增指标白名单、维度/组织过滤、分页明细，并与汇总使用同一权限和统计口径 |
| 统计导出 | `GET /analytics/export` 携带当前 `groupBy/departmentId/teamId/ownerId` | 当前导出路由存在，但接口说明只覆盖 `date/period/resource` | **不匹配**：导出必须复用页面当前过滤器和权限范围，不能导出比图表更多或更少的数据 |
| 个人资料 | `PUT /profiles/me` 提交 `introduction/phone/email/gender/age/avatarAttachmentId/version` | 路由存在，但当前字段白名单仅覆盖头像和简介 | **不匹配**：补齐字段白名单、手机号唯一性、版本冲突和本人头像归属校验；姓名/部门/职位/角色继续只读 |
| 个人重点、公司重点、通知、附件、审核、AI 作业与 AI 地图 | 见 `repository.dart`、`ai_repository.dart`、`ai_work_repository.dart` | 已找到对应服务端路由或应用服务入口 | **已登记**：继续以服务端实际 OpenAPI/权限/版本语义为准，不能以 Mock 通过作为完成证据 |

### 审计边界

- 本次没有新增、修改或删除任何服务端 Controller、Service、迁移或测试。
- 工作区原先存在的 `server/.../TaskQueryService.java`、`server/.../TaskController.java` 差异已保留，不能视为本次审计已实现；服务端需自行确认其来源、测试和正式 OpenAPI 状态。
- 移动端现有 Mock 只用于页面和交互验收。完成后端实现前，上表中的“缺失/不匹配”链路在移动端仍应标记为未联调。

## 约定与边界

- 以下是移动端已接入的 HTTP 形状或 OpenSpec 要求的目标契约。Mock 通过只证明移动端交互，不证明服务端鉴权、持久化、事务或数据完整性。
- 本阶段明确只改移动端。此文档不授权或记录任何服务端实现完成。后端实现前，应核对真实 controller/service、`docs/backend-interface.md`、`docs/openapi.json` 与 OpenSpec；若当前服务端冲突，按本文列出缺口，不降低移动端需求。
- 日期窗口统一按 `Asia/Shanghai` 业务日解释，日期范围采用左闭右开 `[from, to)`；任务区间查询必须处理跨界任务。组织范围必须基于当前会话和当前关系实时校验。
- 列表沿用分页信封 `{items,total,nextCursor}`（cursor 可为空）；版本化写操作返回最新版本/状态，错误沿用项目统一错误信封，使客户端可区分 400 校验、401/403 权限、404 不存在、409 版本/幂等冲突及 5xx/不可用。
- 不得让客户端指定审核人、伪造 founder 身份、猜测组织范围，或用服务端缺字段推导“已完成/未提交/零值”。

## 契约缺口清单

### A. 月视图与成员任务日历（#1–#3、#12）

移动端现有任务列表 HTTP 映射为 `GET /tasks`。日历将日期网格覆盖的上海时间范围以 ISO-8601 `from`、`to` 传入；月历区间是可见首周周一到末周后一周周一，而不只是自然月。成员任务日历另传 `ownerId`。服务端应支持：

```text
GET /tasks?from=<inclusive-ISO8601>&to=<exclusive-ISO8601>&ownerId=<optional-id>
```

返回所有授权且与窗口相交的任务，条件为 `start_at < to AND deadline >= from AND deadline >= COALESCE(start_at, deadline)`；缺失 `start_at` 时按 `deadline` 作为起点。按当前组织范围校验 owner，完整分页。这样月初/月末灰色日期、跨月任务和下属任务都能与主视图使用同一记录数据。移动端不能在接口漏记录时自行合成跨月胶囊。

**当前差异需确认：**本地未提交的服务端变更把 `date/period` 查询改为按任务区间相交，并对 `period=month` 扩展网格；移动端月历实际发送的是 `from/to`，成员任务还发送 `ownerId`。需由后端核实两种参数是否都受支持、边界时区/排他性是否一致。该差异尚未经过正式联调。

### B. 日志首次提交与 24 小时直接修改（#6–#8）

移动端新增日志仍通过现有日志创建资源提交单字段 `work`（兼容显示字段为“今日工作”）；现有日志查询需允许按有权日期浏览。正式服务端必须：

- 仅允许本人对上海今天、昨天、前天尚无已提交日志的日期首次提交；草稿不算提交。保存首次 `submittedAt`，编辑期限为 `submittedAt + 24h`，不是自然日结束。
- 新增或正式兑现：

```text
PUT /logs/{id}/content
{ "work": "...", "version": 7 }
```

本人首次提交后 24 小时内可直接修改正文，无需审核。服务端原子校验作者、状态、当前版本及截止时间，更新正文并递增版本，记录修改历史；必须保持原 `submittedAt`/`editableUntil`，不能因修改重置窗口。满 24 小时后只读。
- 过期、越权、草稿/撤回/状态不兼容、空正文和版本冲突需返回可区分错误；任何失败不得部分写入。旧修订/撤回重提路径不得延长首次提交窗口或让旧候选覆盖新正文。
- `GET` 详情建议明确返回 `submittedAt`、`editableUntil`、`version`、作者和业务日期；上级只读已提交正文与评论，不得读取本人本地未提交草稿或私人备注。
- 移动端已停用阅读登记。保留历史数据不要求删除，但不再依赖“已读回执”改变日志内容或统计。

**尚未兑现/验证：**真实服务端三日首次提交、独立 24 小时直接编辑、事务/并发冲突、旧候选失效、查询授权及截止后只读。

### C. 个人资料与联系人读取（#9、#12）

移动端个人资料保存目标：

```text
PUT /profiles/me
{
  "introduction": "...",
  "phone": "...",
  "email": "...",
  "gender": "...",
  "age": 30,
  "avatarAttachmentId": "...",
  "version": 4
}
```

仅提交当前编辑字段也可接受，但服务端必须执行白名单；本人可改简介、手机号、邮箱、性别、年龄及本人上传头像，姓名/部门/职位/角色等组织身份字段不可由此接口修改。手机号需原子更新权威用户手机号并保持唯一约束；重复号码/版本冲突不得部分保存。年龄只要求符合既有非负整数校验，不新增产品未约定上限。

`GET /profiles/{id}`（本人及有权上级使用）需在授权范围返回真实 `phone`、`email`、`gender`、`age`、`version`、简介、头像和只读组织资料。联系方式的读取权限限本人、真实组织关系中的直属及递归上级，以及既有合法组织管理员；不可按“更高角色”向无关人员或同级开放。每次读取按当前组织关系检查，调岗/撤权后旧上级应失去访问。

**尚未兑现/验证：**正式 `/profiles/me` 字段白名单/版本、电话唯一和权威身份同步、上级祖先读取授权、撤权后缓存失效。

### D. 多维统计、图表钻取与同范围导出（#10）

移动端汇总查询目标为 `GET /analytics`，基础参数：

```text
date=YYYY-MM-DD&period=day|week|month&groupBy=department|team|person
&departmentId=<optional>&teamId=<optional>&ownerId=<optional>
```

汇总需返回请求范围/粒度/更新时间、条形分组与可用趋势桶、按期验收率和日报提交率的分子/分母；图表指标至少覆盖派发、接收、反馈、验收、逾期、日报提交。任务阶段分布使用真实事件时间；缺失的历史事件不得用当前任务状态伪造历史趋势。零分母须明确表示无可计算比率，不能伪造 0%。

新增详情契约：

```text
GET /analytics/details
  ?date=...&period=...&groupBy=...&departmentId=...&teamId=...&ownerId=...
  &metric=<allowlisted-metric>&groupId=<optional>&bucket=<optional>
  &cursor=<optional>&limit=30
```

返回 `{items,total,nextCursor}`，明细和汇总采用同一授权范围、过滤器与指标口径。非法指标/维度拒绝；钻取期间权限被撤销时停止返回该范围数据。

现有移动端导出调用 `GET /analytics/export`，除 `date/period/resource=logs|tasks` 外，传递当前 `groupBy/departmentId/teamId/ownerId`。汇总、图表、分页明细与 CSV 必须共用相同过滤和权限范围，避免导出比界面多或少数据。

**尚未兑现/验证：**真实多维聚合、部门/团队/员工权限过滤、事件历史、详情分页、零分母语义和同范围 CSV。当前 Mock 从模拟任务/日志及显式事件时间计算，不能视作真实统计证明。

### E. 下属日志月状态（#12）

移动端已接入：

```text
GET /logs/subordinates/calendar?ownerId=<id>&month=YYYY-MM
```

响应形状：

```json
{
  "ownerId": "...",
  "month": "2026-10",
  "employmentStartDate": "2025-01-01",
  "days": {"1": "SUBMITTED", "2": "MISSING", "3": "FUTURE", "4": "UNKNOWN"}
}
```

每一天需按该成员真实在职日期、当前业务日及已提交日志计算状态；只有可确认应存在日志而没有提交时才返回 `MISSING`。未来日和无法确定的状态分别返回 `FUTURE`、`UNKNOWN`，不能把接口失败、历史未迁数据或入职前日期判成缺交。仅授权上级读取，返回范围必须匹配请求的 owner/month。点选已提交日期后，现有日志详情接口必须只返回该成员已提交内容及评论所需字段。

**尚未兑现/验证：**正式端点、成员范围鉴权、准确入职日与逐日状态、成员已提交日志分页/日期筛选以及撤回后的状态一致性。

### F. 导图公司任务卡片（#13）

新增移动端资源：

```text
GET /tasks/received-card?cursor=<optional>&limit=<n>
```

需返回当前会话有权查看的接收任务完整分页，记录至少含 `id/title/version`、真实 `dispatchAt`（来自派发事件时间）、当前 `phase`（至少区分进行中、已验收、已归档、已撤回）及卡片实际展示所需字段。客户端按 `dispatchAt` 倒序，同一时间按 ID 稳定排序；未知派发时间置后。已验收/已归档历史必须保留供删除线灰字展示；撤回不伪装为完成。只有确实没有授权历史记录时才返回空列表，不生成占位“已完成”记录。

**尚未兑现/验证：**正式路由、全量授权历史分页、派发事件时间、当前阶段和撤回/完成区别。

### G. 个人重点与公司重点详情（#14–#15）

- 公司重点：现有授权列表/详情读取需支持按记录 ID 读取指定标题和正文，并在权限撤销后拒绝详情读取。移动端弹卡会在账号/授权列表变化时清空过期正文；服务端须确保列表和详情遵循同一组织范围。公司重点只读，私人备注继续走独立资源。
- 个人重点：移动端使用 `dashboard/personal` 独立记录，创建/保存/归档经 `POST /dashboard/personal`，字段至少含 `id,title,text,position,pinned,archived,version`。服务端须限定本人写入、版本冲突、最多十条置顶及合法排序/归档；不得读写个人资料字段。读取和详情只对本人可见，保存失败返回冲突/权限错误且不吞掉输入。

**尚未兑现/验证：**请后端核对个人重点现有 API 是否已满足版本化写入、本人范围与置顶限制；移动端 Mock 能力不等于正式契约完备。

### H. 直属单级审核与创始人免审（#17）

`GET /reviews` 和 `GET /reviews/{id}` 需为每条待审申请提供顶层 `applicant_id/name`、`status`、`reviewer_id/name`、`reviewer_configured`、`approval_mode=DIRECT_MANAGER`、`expected_version`、候选/当前值、申请理由与只读历史事件。历史 `steps` 可保留审计，但不得再被客户端解释为多级待办链。

审核决定沿用：

```text
POST /reviews/{id}/decision
{ "approve": true, "reason": "...", "expectedVersion": 5 }
```

客户端不传 reviewer。服务端决定时重新核对待审状态、申请版本、申请人不是本人、当前审核人仍是申请人的有效直属上级；驳回必须有理由。批准即生效，不再转团队/部门/公司审核；无有效直属上级则保持待审并返回 `reviewer_configured=false`。

所有原本需要关键变更审核的资源修改都应由服务端按当前组织关系创建唯一直属审核任务。有效创始人对原本有权限的操作仍需通过字段/版本/组织范围校验，然后同事务直接生效并留下 `APPROVED` 审计记录及 `decision_source=FOUNDER_EXEMPT`，不生成待审项。创始人免审不得扩大业务写权限；管理员不自动视为创始人。业务写入、审计与通知/outbox 应保持原子一致。历史已决定记录保留；旧多级待审不得把中间批准冒充最终批准，迁移要保留旧步骤审计、重建当前唯一审核人，且不得自动执行创始人历史候选。

**尚未兑现/验证：**正式审核 DTO、所有业务 kind 的直属路由、决定时关系/版本复核、无直属上级待审、创始人事务免审与审计/outbox、旧待审迁移和多级策略/API 退役。

## 后端接手验收要求

1. 逐端点更新 OpenAPI 与 `docs/backend-interface.md`，保证权限、参数、响应、错误、版本/幂等语义与实现一致；补相应服务端单元/集成测试及必要数据库迁移说明。
2. 使用真实数据证明任务月网格跨界、日志上海三日/提交后 24h 的精确边界与并发版本冲突、资料祖先权限/撤权、统计钻取与导出同范围、成员逐日状态、接收任务历史排序数据、所有审核 kind 的单级/创始人策略。
3. 对未知/空数据、越权、组织关系变化、失效版本、幂等重放、分页和服务异常分别验证；不得用 Mock 输出或客户端隐藏控件代替服务端授权证据。
4. 服务端接口兑现后，回到移动端运行真实 HTTP 契约与端到端验收，并把已解决缺口和证据回写 OpenSpec；在此之前相应正式链路保持“未验证”。

## 实施状态备注

本文件基于截至 2026-10-24 的移动端 Repository/Mock 映射与 OpenSpec 设计整理。`TaskQueryService.java`、`TaskController.java` 及 `docs/backend-interface.md`、`docs/openapi.json` 在当前工作区有未提交差异；其来源和正式有效性尚未核实，本文不将这些差异视为后端缺口已关闭的证据。
