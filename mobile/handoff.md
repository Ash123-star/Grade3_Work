
## 2026-10-29 数据库与统一验收更新（取代此前本批未执行验收的状态）

用户已授权最终编译测试，且明确无需同步其他实际开发数据库。独立本地 PostgreSQL 已执行 server Flyway V1–V23；升级、资料列、历史数据保留、确认回执约束及核心 HTTP 契约得到运行验证。V22/V23 满足当前实现的数据存储需要，无需新增重复字段。最终后端定向 41 项通过、移动端定向 35 项通过，后端打包、Flutter analyze、正式接口模式 Android APK、Web build 均退出 0；运行服务已重新导出 docs/openapi.json。

整体仍未验收通过：最终 Flutter 全量 281 通过、3 跳过、44 失败；后端此前全量 425 项中139失败、21错误，修复后只重跑受影响定向组，不能外推全量通过。另保留设备、部署镜像数据库版本、真实供应商及 OpenAPI 展示警告等待验证。具体命令、日志、缺陷修复和剩余动作以 `../docs/database-contract-verification-2026-10-29.md` 为最新依据。HCJ 工作区混合改动未提交/推送。
# Mobile 阶段交接

更新日期：2026-10-29（Asia/Shanghai）
范围：`mobile-page-experience-refresh` 的移动端实现、验收状态和当前前后端接口联调交接。本文用于新会话接续，不代表阶段交付或验收通过。

## 本轮接口补齐状态（2026-10-29，优先于下方历史审计）

P0六组及直属上级单级审核/#17已有源码接入，详见 `../docs/mobile-p0-implementation-status.md`。后续已接通任务退回、成果反馈附件、团队目录、AI SELF/AUTHORIZED范围及带version的事务内确认/幂等回执，复用已有任务评论与日志回复；详见 `../docs/mobile-remaining-api-implementation-status.md`。团队目录Mock权限与服务端对齐，AI详情展示作业实际范围。

用户明确取消意见反馈：移动端support表单、帮助页入口、我的反馈资源及Mock支持已移除，旧深链回帮助页；保留任务成果反馈和AI分析评价。停用的日志阅读登记不新增阅读人员清单。MEMBERSHIP仍由管理员确认，不适用创始人免审。

V22、V23迁移文件已新增但均未执行，实际数据库尚未更新。按用户要求，本轮不运行测试、分析、编译、构建、服务启动或规范校验；所有接口仍待最终集中验收，OpenSpec任务不勾选。`docs/openapi.json`仍为旧快照，最终从真实运行服务重新生成。工作区含其他模型/用户改动，未提交、推送或创建PR。

## 2026-10-29 前后端接口审计与下一步（当前）

审计基线：分支 `HCJ`，审计开始时 HEAD 为 `8d4209e`（`Merge pull request #33: week6 Flutter log contract adaptation`），工作区干净。本次核对了移动端 `HttpRepository` / 模型 / 页面调用点、服务端 Controller 与查询服务、`docs/openapi.json`、`docs/backend-interface.md` 和 `docs/mobile-openapi-contract.yaml`；当时未运行真实服务端联调，也未修改前后端业务代码。下表是**审计开始时的代码快照**，不是当前工作区的状态。

之后已出现一批服务端、Flutter 适配和 V22 迁移草案。当前 `HCJ` 工作区有未提交的混合改动，含 `mobile/handoff.md`、OpenSpec 文档、Flutter Repository、多个服务端模块和未跟踪迁移；这些改动目前没有编译、自动化测试或真实 PostgreSQL 联调证据。DeepSeek 开发前必须重查 `git status`、HEAD 和完整 diff，逐项复核现有草案，保留既存 `CLAUDE.md` 等无关文件，不得以本表的旧状态覆盖当前事实。

| 优先级 | 接口/链路 | 移动端当前请求 | 当前服务端实现 | 缺口与下一步 |
| --- | --- | --- | --- | --- |
| P0 | 导图接收任务卡片 | `GET /tasks/received-card?cursor&limit&search` | `TaskController` 没有此 GET 路由 | 新增有权接收历史分页及 `dispatchAt/phase` 等卡片字段；验证撤回、验收、归档和稳定排序。当前页面会直接调用该资源，真实服务端无法满足。 |
| P0 | 月视图/成员任务日历 | 页面构造带 `from/to` 的 `Query`，但当前 `HttpRepository._query()` 仍序列化为 `date/period/participantId`，没有实际发出范围参数 | 审计基线的 `TaskController`/`TaskQueryService` 不绑定 `from/to`，按截止时间过滤而非任务区间相交；当前工作区有未验证的范围查询草案 | 同步修正移动端序列化与服务端筛选：真正发送可见网格 `from/to`；兼容旧 `date/period`，按任务时间区间相交并校验参与人范围。`Query.ownerId` 在任务请求中对应 `participantId`。 |
| P0 | 下属日志日期筛选与月状态 | 页面构造带 `from/to/ownerId` 的 `Query`，但当前 `HttpRepository._query()` 没有序列化 `from/to`；月状态请求 `GET /logs/subordinates/calendar?ownerId&month` | 审计基线的 `/logs/subordinates` 未绑定 `from/to` 且没有 calendar 路由；当前工作区有未验证的范围和 calendar 草案 | 修正实际 HTTP 序列化；月状态完整返回上海月内 `SUBMITTED/MISSING/FUTURE/UNKNOWN`，使用可信入职日期和当前组织祖先权限，并让列表、月历、详情授权一致。 |
| P0 | 已提交日志正文编辑 | `PUT /logs/{id}/content`，body `{work,version}` | `LogController` 无此路由；当前有草稿、提交、修订、撤回等接口 | 实现服务端 24 小时窗口、作者/状态/版本原子校验、历史留存和可区分错误，再接真实 HTTP 与并发冲突测试。 |
| P0 | 统计汇总/图表钻取/导出 | 汇总发送 `date/period/groupBy/departmentId/teamId/ownerId`；钻取请求 `GET /analytics/details`；导出附带相同筛选 | `/analytics` 只绑定 `date/period`；当前响应含 `dispatched/overdue/onTimeAcceptance/dailySubmission/unreadLogs/departmentDistribution`，没有移动端读取的 `groupedComparison/taskPhaseDistribution/trend` 等字段；没有 `/analytics/details`；`/analytics/export` 只绑定 `date/period/resource` | 组织过滤参数不会形成服务端筛选，响应结构不足以绘制当前多指标分组柱图、趋势图和阶段分布；钻取路由缺失，导出与界面筛选不一致。按同一授权范围补全汇总、分页明细和 CSV，并验证零分母及历史事件口径。 |
| P0 | 本人资料保存与回读 | `PUT /profiles/me` 可发送 `introduction/phone/email/gender/age/avatarAttachmentId/version`；页面通过 `GET /profiles/{id}` 回读 | `DashboardController` 白名单仅接受 `introduction/avatarAttachmentId/version`；`publicUser` 不含 phone，`profile` JSON 是另一数据源 | 手机、邮箱、性别、年龄任一字段随请求发送都会被拒绝为未知字段；回读目前也不能保证返回登记手机号等资料。补齐权威字段存储/读取、唯一性和版本冲突验收，组织身份字段仍只读。 |
| P1 | 任务创建字段（已从旧缺口中移除） | `_taskDraft` 发 `title/participants/startAt/deadline/group/content/urgency/labelId/attachments` | 当前 `TaskDraftNormalizer` 接受并规范化上述字段；任务列表投影含 `participants` 与 `label` | 当前代码字段映射与服务端白名单基本匹配，不应沿用旧交接中“participants/startAt/labelId 不支持”的说法；仍需用真实服务端验证响应字段、标签权限和任务创建/修订链路。 |
| P1 | 任务评论与回复 | `GET/POST /tasks/{taskId}/comments`，创建请求可带 `parentId` 和 `Idempotency-Key` | `TaskCommentController` 已提供 GET/POST；需核对服务层返回信封、父评论同任务校验和幂等重放 | 路由已存在，不再列为缺失接口；联调仍需验证分页/响应字段、越权、跨任务 parentId、重复键和通知事务。 |
| P1 | 任务退回补充 | 客户端 `tasks` 写入映射遇到 `action=return` 会显式抛 unavailable，不发送 HTTP | 服务端 `/tasks/{id}/events` 与 `TaskLifecycleService` 已支持 `RETURNED` | 若当前产品仍要求此流程，补上 Flutter 事件映射和按钮/状态回读，随后验证角色、阶段、必填说明及版本冲突；这是客户端未接通，不是服务端缺少事件。 |
| P1 | 意见反馈 | Flutter 通用页面调用路径未登记在 `HttpRepository` 路由表 | 当前服务端未找到反馈 Controller/OpenAPI 路由 | 正式反馈读写仍缺完整接口；建立契约后再接入，不把页面/Mock 当作真实提交。 |

### 契约文档状态

- `docs/mobile-openapi-contract.yaml` 是明确标记为 **PROPOSED** 的移动端协议草案，不代表 Controller 已实现。其声明的 `received-card`、成员日志日历、日志正文编辑、统计详情等路径在当前运行时 Controller/OpenAPI 中缺失；任务评论路径已由当前 `TaskCommentController` 提供，后续只需做响应与权限联调。
- `docs/openapi.json` 是当前生成的运行时契约快照；它没有上述缺失路由。`/profiles/me` 与 `/analytics/export` 虽有运行时路由，但请求白名单/参数仍不足以满足移动端调用。
- `docs/backend-interface.md` 同时记录了部分目标协议，阅读时需和当前 Controller 对照，不可把目标描述当作运行能力。
- [`mobile/docs/backend-contract-gaps-mobile-page-experience-refresh.md`](docs/backend-contract-gaps-mobile-page-experience-refresh.md) 是 2026-10-25 的详细历史记录，含当时工作区状态和部分过时的任务字段判断；本节是本次分支代码核对后的当前摘要。进入接口修复批次时，应同步更新详细缺口文档和 OpenAPI，避免两份交接相互矛盾。
- [`docs/backend-interface-gaps.md`](../docs/backend-interface-gaps.md) 是更早的接口缺口登记；其中任务字段、任务评论和退回事件状态部分已过期：当前服务端已有任务字段映射、任务评论路由及 `RETURNED` 事件，但 Flutter 退回操作仍未接通。实现前应逐项按当前代码复核该登记表，避免重复造接口。

### 下一步：修复前后端接口连接

本批由 DeepSeek 按一个阶段一份交付的方式实施，Codex 每阶段先做差异/权限/架构/测试覆盖审查，通过后再进入下一阶段；所有实现完成后再集中跑自动化验收。接口、文件、动作与案例级验收见 [`deepseek-p0-implementation-plan.md`](docs/deepseek-p0-implementation-plan.md)，OpenSpec 勾选状态见 [`openspec/changes/mobile-page-experience-refresh/tasks.md`](../openspec/changes/mobile-page-experience-refresh/tasks.md)。

实施顺序固定为：①核对并修复当前未验证草案；②迁移与成员生命周期；③任务区间/接收卡片；④下属日志/月状态；⑤日志24小时直改；⑥资料读写；⑦#17审核与历史待审；⑧统计汇总/钻取；⑨同范围CSV；⑩双端映射、运行时OpenAPI与文档同步；⑪集中自动化和真实PostgreSQL验收。阶段审查不等于最终验收；只有真实服务、自动化测试和OpenSpec严格校验的明确结果才能勾任务。

## 当前结论

- 用户 #1–#17 的移动端页面、交互、Mock 与 HTTP 适配均已接入；按点实施记录见 [`openspec/changes/mobile-page-experience-refresh/tasks.md`](../openspec/changes/mobile-page-experience-refresh/tasks.md)。这表示代码路径已建立，不表示每项已经验收。
- 本地 P0 服务端改动已有部分代码草案，但仍属未验证；执行情况、每阶段边界及验收案例以 [`mobile/docs/deepseek-p0-implementation-plan.md`](docs/deepseek-p0-implementation-plan.md) 为准。不得把接口已写入 Controller、OpenAPI 草案或 Mock 响应报告为功能完成。
- 2026-10-24 历史验收记录：`openspec.cmd validate --all --strict` 38 项通过、0 项失败，退出码 0；`D:\flutter\bin\flutter.bat analyze --no-pub` 无问题，退出码 0；Mock release APK 构建退出码 0。此结果不代表 2026-10-29 当前代码已重新验收。
- 完整 `flutter test --no-pub` 的 2026-10-24 历史结果：267 项通过、31 项失败、2 项跳过，退出码 1。失败覆盖 AI 工作台、Demo/路由、日志流程、月历、下属工作台和 HTTP 契约测试；明细见 [`openspec/changes/mobile-page-experience-refresh/verification.md`](../openspec/changes/mobile-page-experience-refresh/verification.md)。这是历史快照，当前代码尚未在本次接口审计中重跑；所有功能验收 task 仍未勾选。
- 月历定向测试确认 Mock 月查询包含 `t6`，但 UI 未渲染所期待的跨周片段（`calendar_agenda_test.dart:310`）；缺陷定位在数据读取之后，具体轨道/布局原因尚未确定。
- APK 已构建但未安装或手工操作。360/390/412dp 真机/模拟器验收、滚动帧性能、TalkBack/减少动画证据仍缺；正式服务端契约也未联调。不能宣称本阶段已完成。

## 已接入的核心工作

- **月视图 #1–#3**：`+N` 溢出计数、跨周续段标题、连续纵向月份流及跨月查询适配已接入。定向验收未通过：拥挤月份测试中 `t6` 已由 Mock 查询返回，但 `month-span` 未渲染；当前断言在 2026-10-12 周片段处失败，尚未证明 2026-10-19 续段。
- **任务表 #4–#5**：新表格页、固定字段行、横向列浏览/筛选及视图页入口已接入；“我的”旧入口移除，旧路由保留。测试需引用 `task_management_table.dart` 中当前路由使用的组件。
- **日志 #6–#8**：单字段底部编辑层、自动本地草稿、提交、24 小时编辑窗口适配、精简详情及移除阅读登记已接入。卸载时草稿保存曾访问已失效的 Riverpod `ref`，已改为缓存 `DraftStore`；待复验。
- **我的 #9–#11**：原地编辑个人资料与头像、扩展统计图和钻取/筛选契约、审批页奶油白布局已接入。
- **下属 #12**：员工资料头卡、日志提交状态月历及复用主月历的任务视图已接入。
- **导图/全局/审核 #13–#17**：公司任务派发时间排序、公司重点只读居中卡、个人重点独立编辑卡、清除业务演示文案（保留设置中的演示控制）、直属单级审核与创始人 Mock 免审适配已接入。

## 验收修复进度

- 当前完整测试有 31 项失败（不是交接前记录的 38 项）；除月历续段外，还包括 AI 输入/发送状态、旧 Demo UI 入口/表单假设、日志工作流、成员资料字段、任务表入口和日志 HTTP 契约等断言。逐项修复前应核对变更后的产品路径，不能用改弱需求的方式让测试变绿。
- `flutter analyze --no-pub` 已在当前工作区通过；Mock release APK 已成功构建，但 Flutter 提示找不到 CupertinoIcons 字体族，仅找到 MaterialIcons，需确认产品实际界面图标与打包字体。
- `flutter pub get` 因访问 `github.com/flutter/goldens.git` 网络超时失败；验收命令使用 `--no-pub` 复用现有依赖。Android APK 已构建但未安装或手工验收。服务端时间强制、组织权限、统计历史聚合、完整成员日志日历和正式单级审核事务均未验证。

## 移动端 OpenSpec 与设备验收待办

1. 接口联调批次完成后，重新运行移动端完整测试；按 `verification.md` 逐项确认失败属于产品缺陷、过期测试还是夹具问题，不能为了变绿而弱化需求。
2. 集中执行移动端测试、`flutter analyze --no-pub`、Mock APK 构建和 `openspec.cmd validate --all --strict`，保留明确退出码；再安装 APK 按 `requirements-audit.md` 验收 360/390/412dp、1.5 倍字号、月历、表格、日志、图表、弹卡及权限变化。
3. 真实服务端联调、设备验收和逐项验收报告完成前，保持所有功能 task 未勾选。是否提交/推送/创建 PR 需按本批授权、Issue 和工作区状态另行核验。

## 约束与入口

- 用户限定只修改移动端；服务端冲突记录为契约缺口，不能通过更改移动端弱化用户需求，也不修改服务端代码。本阶段后端待补契约见 [`mobile/docs/backend-contract-gaps-mobile-page-experience-refresh.md`](docs/backend-contract-gaps-mobile-page-experience-refresh.md)。
- 保持奶油白/团团主题，只使用现有 `app_theme.dart` 主题角色；新交互使用项目主题化组件，避免直接使用不符合现有视觉的 Flutter 成品控件。
- 每次实现只对应一个原始编号；所有实现完成后集中统一验收。具体细项、依赖和未勾状态以 OpenSpec 为准。
- 本次审计开始时当前分支为 `HCJ`、HEAD 为 `8d4209e`，工作区干净；本次只更新本交接文档。后续开始编码时须重新检查分支和工作区，保留其他成员的新改动。
- 新会话先读本文件、上述 OpenSpec change 的 `proposal.md` / `design.md` / `requirements-audit.md` / `tasks.md`，再检查 `git status` 和相关移动端实现。后端接手者先读后端契约缺口文档，并与当前 `docs/backend-interface.md`、`docs/openapi.json` 及真实服务端实现核对。
