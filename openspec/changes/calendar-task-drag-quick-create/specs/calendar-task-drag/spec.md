## ADDED Requirements

### Requirement: Drag candidates occupy a separate row and expand crowded weeks

故事 C-09；P0。候选任务 SHALL 与目标日期范围内已有条带分行，保持正式任务位置；不足一行空间时 SHALL 向下增高该周并推移后续周，不能裁切候选或月底。

#### Scenario: A candidate intersects occupied rows
- **WHEN** 拖入任务的任意日期与已有条带同一行重叠
- **THEN** 候选 SHALL 进入下一条可用行，跨周／跨月片段保持完整日期与时长，源任务不与自身竞争

#### Scenario: Expansion while hovering and cancellation
- **WHEN** 手指停留时周高度发生变化，随后松手或取消
- **THEN** 布局变化 MUST NOT 自行改变业务日期，确认 SHALL 与最后展示日期一致；取消 SHALL 恢复原排布且不提交改期

### Requirement: Released placement matches the displayed candidate and reads remain bounded

故事 C-08；优先级 P0；范围为长条移动的一致性及月历读取。客户端 SHALL 用同一不可变落点候选呈现完整日期区间并进入确认；月历读取 SHALL 复用短时成功结果并遵守服务端限流，不扩大改期权限或更改抓取日语义。

#### Scenario: A continuation is released between frames
- **WHEN** 用户从长任务中间日或续段拖到另一周／月，随后在下一次预览绘制前松手
- **THEN** 确认框 SHALL 使用最后已显示的抓取日映射及完整候选区间，不根据松手重新命中而静默替换日期，任务时长保持不变

#### Scenario: Repeated navigation and notification bursts
- **WHEN** 用户多次拖动或来回访问刚加载的月份，期间有一批通知到达
- **THEN** 同一月份 SHALL 在有界短时保留期复用完整读取结果，通知 SHALL 由统一去抖入口刷新，月历界面不得再次全局刷新

#### Scenario: A calendar read is rate limited
- **WHEN** 服务端返回 429，且用户继续重试或翻动月份
- **THEN** 客户端 SHALL 在 Retry-After 指定时长或缺省 60 秒冷却内停止新的月历请求，提供冷却提示及之后的恢复入口；既有完整数据只可保留只读展示，鉴权失败 MUST NOT 沿用旧数据

### Requirement: Long press picks up an authorized calendar task

故事 C-01；优先级 P0；范围为“视图→月”的可见任务条。作为有改期资格的用户，我希望长按任务进入拖动，以便直接在月历调整排期。月历 SHALL 在长按达到阈值后显示浮动任务预览，并给出可用的触觉及视觉反馈；短按 SHALL 保持现有点击行为。已知不允许改期、能力标志缺失或只读场景 MUST NOT 启动写入交互。

#### Scenario: Pick up a task with current permission
- **WHEN** 服务端动作能力允许改期，用户在任务条上保持有效单指长按
- **THEN** 月历拿起该任务并显示其身份和原排期，原任务保留可识别参照，不提交任何请求

#### Scenario: A short tap or early scrolling movement
- **WHEN** 用户短按，或在达到长按阈值前开始纵向滚动
- **THEN** 执行既有点击或滚动，不拿起任务、不创建任务、不提交改期

#### Scenario: A read-only or unauthorized calendar
- **WHEN** 用户查看下属只读工作台、失效／待确认账号内容，或服务端未提供改期能力
- **THEN** 月历不开放任务拿起及移动操作，现有授权读取行为不因此扩大

### Requirement: Moving preserves the interval using the grabbed date

故事 C-02；优先级 P0；范围为完整任务的按日平移。月历与服务端 SHALL 使用上海业务日期，以手指拿起时实际命中的日期为锚点计算目标日差；开始时间存在时 SHALL 同步平移开始时间与截止时间，保持时长和时刻。任务各跨周续段 SHALL 对应同一 ID，不创建副本；缺少开始时间的任务 SHALL 保持该字段为空。

#### Scenario: Moving a multi-day task from its middle day
- **WHEN** 任务为 2026-11-02 09:00 至 2026-11-04 18:00，用户拿起 11 月 3 日部分并放到 11 月 5 日
- **THEN** 预览及服务端候选均为 11 月 4 日 09:00 至 11 月 6 日 18:00，任务身份及所有非日期业务字段保持不变

#### Scenario: A continuation segment or a deadline-only task
- **WHEN** 用户从跨周续段拿起任务，或任务没有开始时间
- **THEN** 续段使用实际抓取日作为锚点；无开始时间时仅平移截止时间，不补造开始时间

#### Scenario: Zero movement or invalid original interval
- **WHEN** 用户放回同一锚点日期，或原任务时间无法解析、开始不早于截止、平移结果越界
- **THEN** 零位移不发请求；无效数据不产生误导预览，并提示当前排期不可移动

#### Scenario: The device uses a different time zone or daylight-saving rule
- **WHEN** 设备位于非上海时区，或其本地日历跨越夏令时切换
- **THEN** 仍按上海业务年月日标签计算整数日差，预览与服务端相同，不因本地午夜秒数差少移／多移一天

### Requirement: Edge scrolling supports continuous cross-month dragging

故事 C-03；优先级 P0；范围为跨周、跨月、跨年及闰日移动。月历 SHALL 在拖拽指针于可视区域边缘持续停留后，沿既有纵向月份滚动方向自动滚动；命中日期 SHALL 根据滚动后的真实布局更新。离开边缘、松手或取消 SHALL 停止自动滚动，任务身份和日期锚点 SHALL 保持不变。

#### Scenario: Dragging into the following year
- **WHEN** 用户拖动任务到月历下边缘并停留，连续进入下一月及下一年后选择目标日期
- **THEN** 月份内容连续滚动，预览显示实际命中的完整年月日，平移量跨年仍准确，松手后停止滚动并进入确认

#### Scenario: A leap-day target
- **WHEN** 用户跨月拖动到合法闰年 2 月 29 日
- **THEN** 按真实业务日期计算平移，不按固定每月天数或屏幕行号推算

#### Scenario: An adjacent month is loading or failed
- **WHEN** 自动滚动进入尚未加载完成或请求失败的月份
- **THEN** 保留当前拖拽身份和可理解的加载／错误反馈，该区域暂不接受落点；松手不申请改期，不用空月冒充已加载数据

### Requirement: Dragging owns the gesture until it ends

故事 C-03；优先级 P0；范围为任务拖动与点击、空白长按、纵滑和页面横滑的协调。任务进入拖动态后 SHALL 独占本次指针交互；普通滚动和导航在交互结束后 SHALL 恢复。系统取消、多指、路由离开、切后台或会话变化 SHALL 释放 Overlay、计时器和滚动状态。

#### Scenario: A task is dragged across neighboring hit regions
- **WHEN** 已拿起任务的手指经过其他任务、日期文字、空白、底部导航或加号区域
- **THEN** 仅更新合法日期命中，不触发其他任务点击、快捷创建、页面横滑或导航

#### Scenario: Cancellation or an invalid drop before submission
- **WHEN** 用户在网格外松手、按返回取消、插入第二指针或应用进入后台，且请求尚未发送
- **THEN** 恢复原生效任务显示，不产生改期或创建写入，自动滚动停止且后续普通操作可用

### Requirement: Confirmation and pending review preserve effective dates

故事 C-04；优先级 P0；范围为合法落点确认至审核结果展示。月历 SHALL 在非零有效落点后展示原排期、新排期和原因输入，只有明确确认且通过校验后才发送命令。申请待审时 SHALL 保持原生效日期，并给出申请待审反馈；只有读取到服务端生效版本后 SHALL 移动正式任务与刷新相关列表。

#### Scenario: Submit and later apply a move
- **WHEN** 用户填写原因确认移动，服务端返回待审申请，之后独立审核通过
- **THEN** 待审期间正式任务留在原位且候选不绘制为第二条正式任务；审核后重新读取任务，原／新月份、日期清单、列表及详情显示同一新版本

#### Scenario: Empty reason or cancelled confirmation
- **WHEN** 原因只有空白或用户取消确认
- **THEN** 空白原因阻止提交并明确提示；取消结束本次预览，正式日期不变

#### Scenario: Rejection or no independent reviewer
- **WHEN** 申请被驳回，或没有有效独立审核人而保持待审
- **THEN** 日期不提前生效，用户可查看相应原因或待审状态，不将申请成功提示为改期完成

### Requirement: Failed and uncertain submissions recover safely

故事 C-05；优先级 P0；范围为失败恢复、版本冲突、失权和网络未知结果。客户端 SHALL 区分明确拒绝与传输结果未知；同一次命令 SHALL 使用同一持久化幂等键。请求已发送后退出页面 MUST NOT 被解释为已撤销服务端申请。

#### Scenario: Permission or version changes during a drag
- **WHEN** 提交时服务端返回权限拒绝或版本冲突
- **THEN** 撤除本地预览并提示原因；冲突后重新读取最新任务，未经用户重新确认不自动覆盖或重提；失去读取权限时清除受保护任务显示

#### Scenario: The response is lost after the server creates a review
- **WHEN** 请求超时或断连，客户端无法确定是否创建了审核申请
- **THEN** 显示“提交结果待确认”，保留该命令及键，使用原键和原内容重试确认，最终只关联同一个申请

#### Scenario: Page recovery or account change
- **WHEN** 用户在请求发出后离开页面再返回，或切换账号
- **THEN** 同账号可恢复未知结果确认或查询已知申请；账号变化清理本地交互数据，不能用新账号重放旧命令或展示旧受保护数据

### Requirement: Calendar movement has an accessible alternative

故事 C-07；优先级 P0；范围为无法精细拖动、大字体、减少动画及屏幕阅读器。系统 SHALL 提供可访问的“移动到日期”操作，使用同一日期平移、确认、权限和审核链路；反馈 SHALL 包含文字或语义，不仅依靠颜色、动画或震动。主要确认／取消／选择日期操作 SHALL 满足至少 48dp 可触达范围。

#### Scenario: Screen-reader movement without dragging
- **WHEN** 有改期权限的用户通过语义操作或任务动作选择“移动到日期”
- **THEN** 可选择新的开始日期，无开始时间时选择新的截止日期，经确认后产生与拖动等价的命令，不开放任务转派或旧截止时间编辑入口

#### Scenario: Large text or reduced motion
- **WHEN** 字体缩放为 1.5 或系统请求减少动画
- **THEN** 原／新排期、原因、错误与按钮仍可读可操作，目标日期反馈保留，不因压缩字号或关闭动画而丢失功能

### Requirement: Transient previews and stale responses cannot overwrite current state

故事 C-01／C-05／C-07；优先级 P0；范围为预览、请求和会话生命周期。拖拽预览 SHALL 仅保存在临时交互层，不写正式任务缓存；异步结果 SHALL 校验公司／账号、会话代次、交互／请求代次和组件有效性。取消或失败 SHALL 露出最新生效数据，不把抓取时旧快照写回。源任务已更新、归档、撤回或失去读取资格时 MUST NOT 自动重算并提交旧交互。

#### Scenario: A concurrent update arrives during a drag
- **WHEN** 用户拖动版本 7 时，服务端通知版本 8 已生效，随后用户取消或原请求失败
- **THEN** 结束原交互并保留版本 8，不恢复成版本 7，不自动将旧平移量应用到版本 8

#### Scenario: An old response arrives after switching away and back
- **WHEN** 用户 A→B→A 切换、同账号重新登录或快速切月后，旧请求才返回
- **THEN** 旧结果不能重新打开确认、显示旧受保护数据、跳回旧月或覆盖新请求结果，相同用户 ID 不视为相同会话代次

#### Scenario: Layout geometry changes during movement
- **WHEN** 拖拽期间屏幕旋转、尺寸／字体变化、键盘出现或弹层遮挡
- **THEN** 使用更新后的真实命中区域；无法可靠重建或被弹层遮挡时取消交互，不按旧坐标提交到错误日期

### Requirement: Dragging and submission respect finite resource budgets

故事 C-03／C-05；优先级 P0；范围为自动滚动、月份预取、网络确认和本地命令持久化。系统 SHALL 对滚动、加载、重试设置有限预算：单次移动请求初值 15 秒、前台确认预算 45 秒、最多追加 2 次同键确认；新增预取只覆盖相邻前后月，同时最多 2 个任务范围读取。到达边界、进入后台或交互结束 SHALL 停止自动滚动和写入确认重试。

#### Scenario: Repeated network failures exhaust the budget
- **WHEN** 超时／断连／可恢复错误持续出现，或 `429 Retry-After` 超出剩余前台预算
- **THEN** 停止自动确认且保持结果待确认，提供显式同键确认；不换键、不无限重试、不自动创建离线写入队列，明确业务拒绝不重试

#### Scenario: The pointer remains at an unavailable edge
- **WHEN** 手指持续停在可写日期边界或失败月份的边缘
- **THEN** 滚动停止，不重复启动 ticker、不无限请求月份，恢复或旧回调不自动重开拖动

#### Scenario: The command cannot be persisted
- **WHEN** 首次发送前无法安全保存命令及幂等键
- **THEN** 提示可理解的保存失败并阻止发送，不能先提交后生成另一个键补救
