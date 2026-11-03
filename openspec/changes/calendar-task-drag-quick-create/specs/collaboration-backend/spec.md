## ADDED Requirements

### Requirement: Scoped calendar date translation command

故事 C-02／C-04；优先级 P0；范围为兼容扩展 `POST /api/tasks/{id}/reschedules`。服务端 SHALL 支持只包含 `version/moveDays/reason` 的日期平移模式，要求非零整数平移量、有效版本、非空原因及幂等键；SHALL 从当前生效任务计算排期，拒绝客户端借此修改其他业务字段。只有当前已确认有效账号中、对任务可读且具有既有 `RESCHEDULE` 动作资格的派发人或管理员 SHALL 能申请，不因参与任务或具有上级读取权限自动获得改期资格。

#### Scenario: Authorized whole-interval translation
- **WHEN** 有资格用户提交当前版本和有效平移量
- **THEN** 服务端按 `Asia/Shanghai` 业务日平移已有起止时间形成候选，缺开始时间时保持为空，任务身份、时长及所有非排期字段不变

#### Scenario: Unknown fields or invalid input
- **WHEN** 请求混合 `moveDays` 和 `deadline/startAt/candidate`，夹带其他业务字段，缺少原因／键，平移量为零或非整数，或时间非法／越界
- **THEN** 返回明确 `400` 及错误码／`traceId`，不创建审核申请、幂等记录或任务写入

#### Scenario: Pending account or unauthorized actor
- **WHEN** 待确认、停用、失权、仅参与任务或仅有读取资格的用户申请改期
- **THEN** 拒绝请求；可见但无动作资格按 `403` 返回，不可见或跨公司任务沿用 `404` 隐藏规则，不泄露候选或其他公司资料

#### Scenario: A terminal task or stale version
- **WHEN** 当前任务状态不允许改期，或新命令携带过期版本
- **THEN** 返回相应 `409`，不覆盖任务排期，不创建新的有效申请

### Requirement: Calendar movement is applied atomically after review

故事 C-04／C-07；优先级 P0；范围为 `TASK_RESCHEDULE` 候选从创建到生效。服务端 SHALL 使用既有独立审核流程保存原／候选排期；审核通过前旧版 SHALL 持续有效。最终生效 SHALL 重新检查申请人当前资格和任务版本，在同一事务中更新任务时间列与正文、增加一次版本、记录一次时间线／审计并产生 outbox 通知。

#### Scenario: A pending movement request
- **WHEN** 平移申请已成功创建但尚未通过最终审核
- **THEN** 返回可查询的审核申请 ID 和实际待审状态，任务时间、版本及生命周期保持原值，不能用候选污染列表或月历取数

#### Scenario: An independent reviewer approves
- **WHEN** 合格独立审核人按生效审核策略最终批准且任务版本仍匹配
- **THEN** 起止时间、正文时间和版本原子更新，其他业务字段及生命周期不变；同一变更只产生一次生效事件及对应 outbox，后续读取返回新值

#### Scenario: Self review, missing reviewer or rejection
- **WHEN** 申请人尝试自审、没有有效独立审核人，或审核人驳回申请
- **THEN** 自审拒绝，无审核人保持待审，驳回要求原因；所有情况均不提前改变正式任务排期

#### Scenario: Concurrent approval or revoked applicant permission
- **WHEN** 两个申请基于同一任务版本并发批准，或申请人在待审期间失去资格
- **THEN** 同一版本最多一个变更生效；冲突或失权申请不得覆盖任务，失败事务不留下部分更新、虚假已通过状态或重复通知

### Requirement: Durable idempotency confirms uncertain movement results

故事 C-05；优先级 P0；范围为日期平移的新请求模式。服务端 SHALL 将公司／申请人／幂等键与命令摘要、任务和审核申请持久化关联；命令摘要 SHALL 覆盖任务 ID、版本、平移量、规范化原因和申请时约束版本，保留摘要算法版本的兼容重放。新申请与幂等记录 SHALL 同事务提交或回滚；重放仍 SHALL 校验当前身份、数据范围及申请身份资格，但不重新判定创建时的任务版本／状态／约束窗口。

#### Scenario: Identical requests arrive concurrently
- **WHEN** 同一申请人并发提交相同键和相同命令
- **THEN** 只创建一个申请，各请求关联同一审核 ID，不产生多次任务移动

#### Scenario: A replay after the review has changed the task version
- **WHEN** 原申请已经审核生效，用户以原键和相同命令确认先前丢失的响应，且仍有访问及动作资格
- **THEN** 返回原申请及其当前结果，不因原命令版本已旧而创建新申请或误报新的版本冲突

#### Scenario: Reusing a key with a different payload or account
- **WHEN** 同账号同键的任务、版本、平移量或规范化原因不同，或另一账号／公司尝试读取原命令
- **THEN** 同账号同键不同摘要返回 `409 IDEMPOTENCY_CONFLICT`；其他账号／公司不能取得原申请或其候选

#### Scenario: A response is lost or a transaction fails
- **WHEN** 服务端已提交申请但响应丢失，或创建申请／幂等记录中途失败
- **THEN** 已提交结果可通过原键重放确认；未提交事务不留下孤立申请／键，重试至多创建一次申请

### Requirement: Calendar queries include intersecting task intervals

故事 C-03／C-07；优先级 P0；范围为任务月网格查询及生效后刷新。服务端 SHALL 支持同时提供带时区的 `from/to` 表示 `[from,to)`，返回满足 `COALESCE(start_at,deadline) < to AND deadline >= from` 的授权任务，完整执行稳定分页及既有数据范围。范围查询 SHALL 不接受与旧日期过滤混用的歧义请求。

#### Scenario: A task spans two month grids
- **WHEN** 任务开始于前月并持续到当前月，或覆盖整个查询月份
- **THEN** 各相交网格均能分页取到同一任务 ID 和权威起止时间；客户端读取完整分页后不丢失跨月续段

#### Scenario: Exact range boundaries or missing start time
- **WHEN** 任务开始恰为 `to`、截止恰为 `from`，或仅有截止时间
- **THEN** 恰在 `to` 开始的任务不纳入，截止于 `from` 的任务纳入；缺开始时间按截止时刻进行相交判断

#### Scenario: Invalid range or forged data scope
- **WHEN** 缺少范围一端、日期不带时区、`from >= to`、与 `date/period` 日期过滤混用，或夹带越权人员筛选
- **THEN** 无效范围返回 `400`，越权请求按既有权限契约拒绝，不返回范围外受保护任务

#### Scenario: Read after approval from two clients
- **WHEN** 平移审核生效后 Android 和具有相同数据范围的另一客户端刷新月历／列表／详情
- **THEN** 两端读取同一新版本排期，原日期中不再相交的结果移除、新日期结果加入，待审或驳回不会伪造日期变化

### Requirement: Legacy rescheduling and shared contracts stay compatible

故事 C-04／C-07；优先级 P0；范围为旧客户端、既有待审记录及新版动作能力。服务端 SHALL 保留原 `deadline/version/reason` 请求和旧 `TASK_RESCHEDULE` 候选的解释；新模式 SHALL 明确出现在运行时及静态 OpenAPI、接口权限／版本／幂等／错误说明中。列表及详情 SHALL 提供可信的 `capabilities.reschedule` 动作提示，不以完成情况字段承载权限。

#### Scenario: An older client submits or an older request is approved
- **WHEN** 请求只有旧模式截止时间字段，或审核处理部署前保存的截止时间候选
- **THEN** 沿用原截止时间变更语义及审核规则，不强制旧客户端新增平移字段或幂等键，不误移开始时间

#### Scenario: A new client reaches an old deployment
- **WHEN** 服务端不支持平移模式或不提供新动作能力
- **THEN** 新客户端禁用／明确提示该能力尚未可用，不静默退化为只改截止时间，也不以本地修改冒充服务端完成

#### Scenario: Contract consumers inspect actions and errors
- **WHEN** Android 或其他客户端按公开契约读取动作能力、申请结果与错误
- **THEN** 可区分任务 ID、审核申请 ID、待审与生效结果，收到统一 HTTP 状态／错误码／`traceId`；动作能力只用于交互，不作为派发页面的完成或替代状态列

### Requirement: Movement constraints and numeric boundaries are explicit

故事 C-02／C-04／C-06；优先级 P0；范围为新移动及带约束头的快捷创建。服务端 SHALL 返回 `scheduleConstraints` 及版本，初始日期窗口按服务端上海业务年 Y 采用包含的 `[Y-2 年 01-01, Y+8 年 01-01]`；移动后的已有起止日期均 SHALL 在窗口内。新移动 SHALL 要求 `If-Schedule-Constraints-Match`，严格接受正 32 位整数版本、非零 32 位整数日差、规范化后 1–1000 Unicode 码点原因及 1–128 可见 ASCII 字符键，不进行类型隐式转换。该窗口 SHALL 不影响历史读取或旧模式的既有权限和请求契约。

#### Scenario: A valid move to an inclusive boundary
- **WHEN** 新排期端点恰位于有效 `minDate/maxDate` 且约束版本匹配
- **THEN** 该日期边界可作为候选，具体时刻保留；跨出任一端点则拒绝，不夹取或裁短任务

#### Scenario: Malformed types, oversized values or arithmetic overflow
- **WHEN** 数字字段使用字符串、布尔、小数或越界整数，原因为空／超长，键含空白／控制字符，或排期／版本运算溢出
- **THEN** 返回明确错误且不产生写入，不截断数字、文字或日期，不让版本回绕

#### Scenario: Missing or stale constraints
- **WHEN** 新移动缺少／伪造无效约束头，或携带已经过期的版本
- **THEN** 缺失／无效返回 `400`，过期返回 `409 SCHEDULE_CONSTRAINTS_CHANGED`；服务端不信任客户端自报日期窗口，不自动重定目标

#### Scenario: New-mode deployment is incomplete or disabled
- **WHEN** MOVE 候选消费者尚未全部兼容，或新模式已关闭
- **THEN** 不发布可用的新动作能力且不接受新 MOVE 申请；有资格用户仍可查询／同键读取已存在的申请，旧截止时间请求保持兼容

#### Scenario: A pending request crosses the calendar-year boundary
- **WHEN** 申请已经按当时有效窗口形成不可变候选，待审期间服务端进入新业务年
- **THEN** 原命令可按原键／原约束头确认；审核使用存档候选且仍校验当前权限与任务版本，不仅因跨年自动夹日、通过或驳回，新的移动意图使用新约束重新确认

### Requirement: A task version has at most one pending movement request

故事 C-04／C-05；优先级 P0；范围为本变更的 MOVE 模式，不重定其他任务修改的公共审核政策。服务端 SHALL 在任务行锁内阻止同一任务同一生效版本产生多个不同键的待审 MOVE；同键重放 SHALL 先返回原申请。冲突反馈 MUST NOT 泄露无读取资格的申请内容，不自动替换或撤回旧申请。

#### Scenario: Two different keys race for the same task version
- **WHEN** 两个新命令以不同键并发申请移动同一版本
- **THEN** 至多一个创建待审申请，另一个返回 `409 RESCHEDULE_PENDING`，任务不提前生效；只有有权读取原申请时才提供其 ID

#### Scenario: The task already has a newer effective version
- **WHEN** 旧版本仍有待审 MOVE，而用户针对当前新版本发起有效申请
- **THEN** 旧版本申请不阻止当前版本的新申请，旧申请不得覆盖新版本

#### Scenario: An old command is replayed after its outcome changes
- **WHEN** 原申请已通过／驳回，任务状态改变，或新模式被关闭，而原用户仍有访问及申请身份资格
- **THEN** 原键同内容返回原申请的实际结果，不重新走创建／待审占用校验，不产生新申请；失权用户仍被拒绝

### Requirement: Calendar pagination is consistent and bounded

故事 C-03／C-07；优先级 P0；范围仅为本链路 task `from/to` 查询。服务端 SHALL 在一致性读取事务中返回分页及绑定公司／用户／当前授权上下文／过滤／有序任务 ID 和版本摘要的 `snapshotToken`，后续页 SHALL 验证原令牌并重新鉴权。查询初始跨度上限 SHALL 为 62 个业务日，完整记录上限为 5000，客户端整轮上限为 200 页及 45 秒前台总预算（包含至多一次整轮重读）；这些预算及新范围查询的结束游标 SHALL 在契约中明确，不改变旧日期分页行为。

#### Scenario: Records change without a change in total count
- **WHEN** 读取后页前，一条任务被替换、移出／移入区间或排序改变，而总条数保持相同
- **THEN** 返回 `409 CALENDAR_SNAPSHOT_CHANGED`，客户端丢弃整轮部分结果并最多自动从第一页重读 1 次，不能把混合版本拼为完整月份

#### Scenario: Pagination ends normally or the range is empty
- **WHEN** 已读取全部记录，或首屏真实总数为零
- **THEN** 末页无后续游标且实际唯一记录数等于总数；空结果首屏为空且无后续页，不能忽略矛盾页链并判为成功

#### Scenario: A range or record-density budget is exceeded
- **WHEN** 查询跨度超过 62 个业务日、结果超过 5000 条，或客户端达到 200 页仍未完整结束
- **THEN** 超跨度返回 `400 INVALID_RANGE`、超密度返回 `422 CALENDAR_RANGE_TOO_DENSE`，页预算耗尽显示读取失败；不静默截断，不据部分记录计算月历计数，并提供缩小范围或既有任务列表入口

#### Scenario: Invalid page chains or unsupported filters
- **WHEN** 出现令牌缺失／变化、游标越界／循环、重复 ID、空页仍有后续、总数矛盾，或服务端无法兑现指定成员筛选
- **THEN** 明确失败并停止将该结果作为完整可写月历；不能忽略筛选后把其他人的记录标成该成员，令牌不能替代权限校验

#### Scenario: Refresh fails after a complete month was shown
- **WHEN** 新查询失败但已有最后一个完整月份快照
- **THEN** 在授权仍有效时可标明过期并只读展示，刷新完成前不开放移动落点；失去读取资格则立即清除受保护内容
