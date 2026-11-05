## Context

> 状态边界：下文观察和批次授权属于所记日期/提交。最新自动化见docs/backend-validation.md，现行导航/完整任务行以方案和相关specs为准；旧“未测试/未合并”不能作为当前状态，未完成设备/外部验收仍按tasks保留。


2026-11-04 规划阶段已 fetch 并将 `origin/main`（05d6c25）检出到独立工作区。原目录分支 `chore/public-backend-address` 在 19db6f3，含连接配置、详情页等未提交修改；未 stash、reset、覆盖或在原目录 pull。以下PR表为规划时检查快照；用户批准后的实施、真实服务验收与仍未解决的阻塞见 verification.md。

### 远程 PR 状态与合并前置条件

| PR / 检查时 head | 内容 | 观察到的阻塞与处理 |
| --- | --- | --- |
| #55 / c98a7de | 仓库清理 | reviews 为空；先补非作者审阅，确认当前文档链接仍有效 |
| #61 / ade9805 | 月历与节假日、回归修复 | reviews 为空；PR 报告独立分支后端/Flutter通过，未在本轮复验；优先整合以稳定后续日历基线 |
| #57 / 33e3949 | 多创始人互审、任务置顶 | reviews 为空；PR 明列后端456项中51失败/2错误、Flutter31失败，需在整合#61后重验；新增V24/V25、年度V2 |
| #62 / 7e36275 | 组织选人、多标签、多创始人场景 | reviews 为空，Issue未关联；Flutter组件测试未获得完整退出结果；新增V24、年度V2，和#57重号；运行时/快照/接口文档多标签变更需补齐 |
| #59 / 4a96bd | 拖拽改期 | 草稿，base 为 codex/ai-work-assistant；CI构建通过但正文记录完整测试与性能失败。V22和main已占用版本冲突，月历与#61重叠，不能作为已合并依赖 |

GitHub 的 CLEAN/MERGEABLE 仅表示各 PR 相对当前 base 无文本冲突，不表示组合后的迁移、测试与权限一致。依据 AGENTS.md §5「合并前至少由一名非作者成员审阅」「验收不通过时不得合并」，本轮未执行远程合并。上述是检查时快照，实际合并前重新读取 head、checks、reviews。

建议整合顺序为 #55 → #61 → #57/#62 协调迁移版本与共享字段后整合；#59 单独解决基线、迁移和性能门槛。重号处理前必须核对目标库 flyway_schema_history 和是否发布：从未发布的迁移可协调唯一编号；任一已发布就不得改写其文件或校验值，须制定兼容升级方案。不能默认把 V24 重命名就算解决。

### 接口对齐结果

| 区域 | 观察事实 | 本批决策 |
| --- | --- | --- |
| 首页导航 | app_router.dart 仍为导图/视图，默认 /dashboard | 仅更新用户可见名称，保留旧路由和深链兼容 |
| 事件纪 | DashboardController `/dashboard/company` 返回公司已发布且未归档记录，私人备注独立保存 | 改显示名，继续此读取/审核/备注契约；不是另加时间线业务 |
| 任务看板 | TaskQueryService.receivedCard 在 taskScope 上追加 Actor 本人参与的 EXISTS；Flutter receivedTaskCardProvider 已使用此接口 | 权限逻辑基础已对齐，补验多参与人、列表完整性和会话刷新；不能换回组织范围 `/tasks` |
| 老聚合接口 | `/dashboard.companyTasks` 仍使用组织范围且 LIMIT 10，与 received-card 的本人语义不同 | 新首页继续独立模块读取，不能误用旧聚合响应；旧调用者兼容保留，文档明确差异 |
| 参与人 | 当前 tasks 请求/列表使用无角色 participants；旧文档部分仍写主负责人/协作人 | 执行人按所有参与人解释；不按 PRIMARY 过滤、不增加另一个 owner 字段。同步清理本批相关过期文案 |
| 多标签 | #62 received-card 新增 labels，兼容 label；主线尚是单标签 | 以最终合并接口为准，接收列表/详情/客户端字段与 OpenAPI 同步；不把 PR 当成已发布 |
| 每日事项 | mobile/lib、server/src/main 与 OpenSpec 中未发现独立每日事项实现 | 新增独立模块；不能以Mock或静态日历宣称接入 |
| 个人重点 | `/dashboard/personal?ownerId` 允许授权上级读取 | 不复用个人重点保存私密todo，避免继承组织穿透；移除首页块不迁移/删除旧重点 |
| 现有月历 | CalendarContent 直接依赖任务、Record、全局日期provider，私有 MonthGrid 还负责任务跨日条带 | 仅复用日期网格计算和视觉组件，todo使用自己的日期状态、模型和数据源 |

## Goals / Non-Goals

**Goals:** 覆盖用户五项调整；公司信息、参与任务、私人事项各自闭合；适应320/360/390/480dp及大字体；服务端本人隔离、重试幂等和版本冲突可验收；后端与HTTP客户端共享同一契约。

**Non-Goals:** todo与任务/日报/审核/AI联动、提醒和重复事项、离线自动同步、全新设计系统、重做公司页内容、删除历史个人重点和日志、增加Web完整页面。个人事项不是对原个人重点的迁移。

## Decisions

### 1. 方案比较与推荐

| 方案 | 优点 | 问题 | 结论 |
| --- | --- | --- | --- |
| 扩展tasks为私人todo类型 | 可借用任务列表与日历 | 审核、参与人、统计、AI检索与生命周期容易泄露/混入私人数据 | 不选 |
| dashboard/personal增加日期和完成字段 | 改动较少 | 现有上级穿透权限与“仅本人事项”冲突，重点排序语义不同 | 不选 |
| 仅手机本地保存 | 无后端成本 | 换机/跨会话一致性和备份不足 | 不作为默认 |
| 独立personal-todos模块、服务端持久化 | 权限和状态简单，模块边界清晰，可多设备一致 | 需要新增表与HTTP契约 | 推荐 |

日历选择“共享纯日期/布局组件 + 独立业务适配”。直接挂 CalendarContent 会读任务并共享公司筛选；完整复制其任务跨日/审核逻辑会重复维护。先抽出无IO的日期网格工具，新增todo月历；只有确实相同的日期头、选中态组件再提取，不先构建复杂泛型框架。

### 2. 页面结构与视觉

首页顶部为轻量问候/消息入口；其下事件纪、任务看板双列摘要（各2条，查看全部）。窄屏或大字体自动单列，不固定高卡片填满视口。事件纪沿用最多10项置顶语义；任务预览数量不限制完整看板，超过10项仍完整分页可达。

每日事项为全宽月历，标题同行放「＋事项」（48dp），下一行月份/上月/下月/今天，周一为周首。日期格只放日期、待办数量/完成标记，完整标题放下方选中日清单；大字体可滚动，不把长标题挤入七列。选中态、今日态、已完成均有文字/形状辅助，不仅依赖颜色。

当天清单有未完成/已完成分组；完成可恢复，编辑可改日期，删除先确认。新增表单预填选中日，标题必填、备注选填。首页个人重点和个人日志卡片消失，日志页仍可用；个人重点数据接口与旧列表/详情深链保持兼容，本批不另增个人重点入口。

沿用现有团团的暖白纸面、淡蓝事件纪、浅杏任务看板、薄荷绿主要操作；16dp页面边距、12dp卡间距、20dp分区间距、20dp圆角，字重和色彩接入现有 ThemeExtension/ColorScheme。降低大面积装饰密度，日历数字和内容更清楚。参考原首页截图与现有PaperSurface；不新增外部素材、字体或框架。HTML原型采用现有仓库图标，标注固定演示数据。

保留有资格用户的圆形任务派发加号，添加可读“派发任务”标签/语义；事项添加是月历内的“＋事项”。滚动底部留出派发入口空间，不能遮挡todo操作；无资格用户不保留浮钮空白。

### 3. 模块与依赖方向

- Flutter `features/home`（可从dashboard迁移组合代码）：只组织 Header、CompanyEventsPreview、ReceivedTasksPreview、DailyTodosSection；不实现SQL/权限规则。
- `features/personal_todos/{data,application,presentation}`：类型化 PersonalTodo、独立Repository接口与HTTP实现、按会话/月份key的Riverpod状态、月历/列表/编辑器。可复用现有HTTP client、ApiFailure和通用分页基础设施，不把业务塞进全局resource字符串switch。
- `shared/calendar`：Shanghai业务日期、周首、网格起止和纯展示参数，无task/log/review import。公司月历仍由任务适配器处理跨日条带/节假日/审批。
- 后端 `module/personaltodo/controller` 绑定校验与Actor；`application` 用例事务、幂等、版本；`domain` 内容限制和状态；`infrastructure` Jdbc仓储。复用认证与错误基础设施，不依赖task、review或log模块。
- 组织权限模块只提供当前已确认账号身份，不以 actor.global() 放开todo读取；管理员也不能代查他人事项。DeepSeek调用范围保持原状，todo不进入检索、摘要、审计正文或普通日志。

### 4. HTTP契约（已实现，验证结果见 verification.md）

根路径 `/api/personal-todos`，仅已确认且有效会话。服务端从Actor写入company_id/owner_id，客户端不能传 ownerId/companyId。采用 `{code,message,traceId}` 错误体。列表GET只读；写请求全部要求 `Idempotency-Key`，更新/删除同时需要版本。

| 方法 | 路径 | 参数/请求 | 成功 |
| --- | --- | --- | --- |
| GET | `/personal-todos/calendar` | `month=YYYY-MM` | `{month,fromDate,toDate,days:[{date,total,completed}]}`；范围覆盖该月周一到周日的完整网格，日期为左闭右开 |
| GET | `/personal-todos` | `date=YYYY-MM-DD,cursor=0,limit=30`（1–100） | `{items,total,nextCursor}`，未完成优先再createdAt/id；末页nextCursor为null |
| GET | `/personal-todos/{id}` | 无 | 本人完整todo；越权/不存在统一404 |
| POST | `/personal-todos` | `{title,note?,date}` | 201完整todo，version=1、completed=false |
| PUT | `/personal-todos/{id}` | `{title,note,date,completed,version}`，全量编辑 | 200完整todo，版本递增 |
| DELETE | `/personal-todos/{id}?version=N` | 无正文 | 200 `{id,deleted:true,version:N+1}` |

返回todo固定字段 `{id,title,note,date,completed,completedAt,version,createdAt,updatedAt}`；不返回参与人、任务ID、审核ID。标题trim后1–120字符，备注0–2000字符；严格校验真实日期、月份、布尔类型、非负cursor及正版本，拒绝未知字段；日期域建议1900–2100并在客户端一致限制。业务日期是PostgreSQL DATE，不转换为UTC午夜；时间戳UTC，展示按Asia/Shanghai。

错误：未登录401；待确认/停用403（沿用认证网关）；对象越权404；无效字段/日期/分页400；旧版本409 VERSION_CONFLICT；同键不同payload409 IDEMPOTENCY_CONFLICT；限流429/服务失败5xx明确提示。过期session清空个人状态，不让旧请求回填新账号。

幂等按 `(company_id,owner_id,key)` 唯一，记录method/path、规范请求摘要、响应状态与最小结果；业务写入和回执同事务。先查同键同请求已完成结果，再执行版本更新，防止成功后网络丢响应重试产生假冲突；同键不同请求拒绝。认证/本人隔离在重放时仍校验。完成操作是设置布尔值而非服务端toggle，重复请求不会翻转两次；网络结果未知保留原key和表单，不能新key自动重发。

### 5. 数据与更新

新增 `personal_todos(id,company_id,owner_id,business_date,title,note,completed,completed_at,version,created_at,updated_at,deleted_at)`，复合外键确保用户公司一致；有效数据索引 `(company_id,owner_id,business_date,completed,created_at,id) WHERE deleted_at IS NULL`。删除为用户不可见墓碑，用于并发/重放，不进入普通审计正文；墓碑清理与幂等保留期统一评估，建议回执24小时。可复用经验证支持本人隔离的幂等基础设施，否则使用此模块专用命令表，不借用task命令表。

每次读写/聚合都带company、owner条件；版本UPDATE在单条SQL中校验且只影响一行。已完成再次设true不改completedAt；恢复后清空completedAt；其他编辑更新version。删除后列表和月计数消失，其他旧版本修改不复活记录。

事项操作成功后精准刷新受影响日期清单、旧/新月份网格；不调用全局refreshBusiness刷新任务、日志和组织。页面恢复前台/拉动刷新重新读取，以实现跨设备可见。首期不接todo SSE；若将来增加通知必须用事务outbox，不能先写库后裸发消息。

加载/空/失败各自独立，todo失败不阻断两个业务摘要。保存失败保留表单；409展示服务器版本并让用户重新编辑；离线明确不可保存，不能乐观显示为已同步。公司月历和todo选中日期独立，跨Tab不互相重置筛选。

## Risks / Trade-offs

- [合并基线尚未稳定] → 用户批准后在已检查的 main 05d6c25 独立实现，不依赖未通过审阅的 PR。V26 避开已占用的 V24/V25；正式发布前必须完成迁移顺序协调和最终合并基线验收。
- [已有个人重点可穿透] → 独立表/仓储/接口，增加同公司上级/管理员、跨公司及id枚举拒绝用例。
- [前端摘要预读全量任务] → 首页只取短页，完整看板按需翻页；避免目前receivedTaskCardProvider一次遍历全部历史的成本。分页途中失败提示未加载完，不当作空或完整。
- [跨请求分页期间有新写入] → 服务端稳定排序，客户端ID去重与刷新；需要完整快照时沿用经验证的快照契约，不承诺offset分页天然一致。
- [“事件纪”容易被理解为时间线] → 本次严格按更名保留原公司重点语义，若要时间轴另提需求。
- [日期格窄于48dp] → 320/360dp七列为例外，保持至少48dp高度和整格可点，完整事项操作在全宽列表保持48×48dp；辅助日期选择器提供标准触控入口，大字体不裁切内容。
- [原型不能证明Flutter实现] → HTML只用于信息层级评审，Flutter截图、TalkBack和真实链路另验收。

## Migration Plan

1. 完成PR审阅、重号与契约处理，在干净整合分支一次验收，完成合并后同步主线；不覆盖原工作区混合改动。
2. 关联Issue/Sprint，按当前方案更新产品基线、AGENTS导航与OpenSpec config，保留历史说明。
3. 新增唯一版本Flyway及从最新主线库升级测试；旧重点、日志不迁移或删除。
4. 后端新增接口先部署并导出运行时OpenAPI，再接入Flutter；旧客户端继续使用原有接口。
5. 验收后提交/推送/PR，不在默认分支直接提交。归档前同步主规格并执行strict校验。
6. 回滚客户端/新端点时保留新增表与回执，不删除用户todo，也不倒退已发布迁移；可通过前向修复恢复。已发布的审核/任务兼容性按各PR自己的回滚约束执行。

## Open Questions

- 各PR的非作者审阅、#57/#62迁移在目标库的执行历史、#59是否保留草稿状态，是实际合并前需解决的外部事实。
- 默认提案为私人todo云端持久化，支持完成/编辑/删除，无提醒和重复规则；若需要仅本地保存或分享，此项需要调整数据设计。
- 本轮仅调整Flutter导航和首页；若要求Web同步重做页面，另补页面范围与验收。
- 负责人和Sprint待关联。新接口、迁移与Flutter已实现；已执行的验收、整库失败和设备限制记录在 verification.md，不能把本批定向通过视为整库发布通过。
