## ADDED Requirements

### Requirement: 视图任务入口与个人月历
视图页 MUST 保留任务管理入口，日周月视图 SHALL 默认仅查询当前用户参与任务。

#### Scenario: 主月历
- WHEN 管理者打开主视图月历
- THEN 请求携带本人参与人ID，不显示仅下属参与的任务，任务管理入口仍可打开授权范围任务表

#### Scenario: 明确成员日历
- WHEN 从人员详情进入指定成员月历
- THEN 请求仍携带指定成员ID并沿用服务端范围校验，不被本人默认筛选覆盖

### Requirement: 公司任务入口与列表一致
导图卡片和列表 MUST 共用当前人员参与任务的分页数据源，SHALL 包含全生命周期记录和本人派发且参与的任务。

#### Scenario: 打开完整列表
- WHEN 用户点击公司任务卡片或查看全部
- THEN 页面展示与卡片同范围的任务且可读取后续分页和任务详情

#### Scenario: 查询失败
- WHEN 列表请求失败
- THEN 页面展示可重试错误而非空任务，重试刷新同一数据源

### Requirement: 日志标题与日期分离
客户端 SHALL 从日志实际正文生成摘要标题，日期 MUST 作为独立元数据保留。

#### Scenario: 有工作内容
- WHEN 正文首个非空行为带序号的工作内容
- THEN 标题展示去序号后的内容摘要而非业务日期

#### Scenario: 无工作内容
- WHEN 正文为空或只有空白
- THEN 标题显示工作日志，不显示日期或内部ID

### Requirement: 人员名称显示真实姓名
任务、日志、审核和审计中的人员展示 MUST 使用同公司人员姓名，SHALL 不把登录账号或内部ID作为缺失姓名的回退值。

#### Scenario: 历史流程
- WHEN 有效范围内的任务事件或审核步骤关联人员
- THEN 返回并展示users.name对应姓名

#### Scenario: 缺失姓名
- WHEN 历史人员姓名不存在或为空
- THEN 显示未知成员占位且不输出内部人员ID作为人名

### Requirement: 人员卡片关联实时业务数据
人员接口 MUST 在当前组织和任务权限范围返回参与任务数及未结束任务数，SHALL 按上海业务日返回今日日志提交状态。

#### Scenario: 真实业务变化
- WHEN 成员获得参与任务或提交今日日志后刷新人员页
- THEN 计数和提交状态反映数据库结果，分页不改变计数

#### Scenario: 未知与隐私边界
- WHEN 账号待确认、接口未返回统计或他人只有草稿
- THEN 待确认和缺失统计显示未知，他人草稿不作为已提交日志且不披露正文，跨公司数据不计入

### Requirement: Business review presentation
The client SHALL render review snapshots as localized business fields and state-aware descriptions, without raw property names or reference IDs. The server MUST resolve only references contained in an already authorized review and in the same company.

#### Scenario: Approved task creation
- **WHEN** an approved task creation review is opened
- **THEN** it shows creation content, resolved names and local business time without an effective version zero or pending approval instruction

#### Scenario: Missing reference
- **WHEN** a referenced label or member is missing or belongs to another company
- **THEN** the display indicates an unavailable name without exposing the identifier or another company's name

### Requirement: Notification navigation and review card width
The client SHALL localize supported notification types including historical TASK_DISPATCHED and navigate to their existing authorized detail pages. Review cards SHALL occupy the available list width.

#### Scenario: Historical task notification
- **WHEN** a user taps a TASK_DISPATCHED notification with a valid object identifier
- **THEN** the task detail opens with a Chinese notification title

#### Scenario: Missing target or failed read marking
- **WHEN** a target is missing or marking the notification read fails
- **THEN** a missing target is explained and a read marking failure does not prevent a valid detail navigation

#### Scenario: Short review title
- **WHEN** a review title and metadata are short
- **THEN** its card still fills the available list width while preserving page margins

### Requirement: Floating operation feedback and organization names
The client SHALL show operation feedback above content without reducing editor or button space, distinguish success, information and error by text and icons as well as color, and preserve recovery actions. It SHALL show authorized team names rather than internal identifiers, and company focus records SHALL use filled bullet markers.

#### Scenario: Repeated feedback with keyboard open
- WHEN a user receives successive operation messages with the keyboard visible
- THEN the newest message replaces the old message without changing the editor or button layout and can be dismissed

#### Scenario: Version conflict
- WHEN a form submission conflicts with a newer record
- THEN floating feedback retains the explicit reload confirmation and local draft preservation

#### Scenario: Missing team name
- WHEN a visible member references a team whose name is unavailable
- THEN the UI shows an unavailable-name placeholder rather than the team identifier

#### Scenario: Company focus list
- WHEN the user expands company focus records
- THEN each record uses a filled bullet while retaining its existing detail interaction

### Requirement: Month task title width
Month task labels SHALL use their weekly segment's full available width rather than a six-character or single-day width limit, reserve 10 logical pixels at the trailing edge, and ellipsize overflow. Cross-week continuation segments MUST repeat the title at the first day of each weekly segment.

#### Scenario: Long duration and short title
- WHEN a task spans several days and its complete title fits before the trailing safety margin
- THEN its entire title is displayed without artificial character truncation

#### Scenario: Cross-week continuation and overflow
- WHEN a task continues into another week with a title too long for that week's segment
- THEN the title repeats at the segment start and is ellipsized before the 10dp trailing margin


### Requirement: Regression-safe overlay and local recovery
The mobile app SHALL preserve human notification titles, release temporary notification timers when their overlay is disposed, and keep recovery actions accessible inside floating feedback.

#### Scenario: Read marker fails on the network
- **WHEN** marking an authorized notification read fails with a network error
- **THEN** the app SHALL warn the user and open its valid target while preserving the unread state

#### Scenario: Account changes with an open calendar day
- **WHEN** the session identity changes or business access is revoked
- **THEN** the calendar SHALL clear the previously opened day records and SHALL NOT query protected month data without an active account

#### Scenario: Legacy revision draft opens in the current diary editor
- **WHEN** the same account opens an identified record/version with a stored revision draft and no daily draft
- **THEN** the editor SHALL restore that local revision and retain its original server version for conflict detection
