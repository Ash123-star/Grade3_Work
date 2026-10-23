## ADDED Requirements

### Requirement: E1 Explicit intent and bounded automatic authorization

系统 SHALL 把用户本次明确指令与资料中的文字分离，只在当前业务权限与明确指令或匹配的有效预授权同时满足时执行写入；只读查询、解析和检查可自动执行。预授权 MUST 默认关闭、限制动作/对象/数量并有期限，可随时撤回。截图、制度文字和模型输出 MUST NOT 自行授予权限或指挥工具。模型不得直接写库、使用任意工具、验收或代审批。

用户故事 E1：作为已确认成员，我希望交代事情后由 AI 在已有权限内直接办理，减少重复确认。优先级：MVP/P0；范围：所有自动动作及其授权；验收标准：以下场景和设计第 3 节权限矩阵。

#### Scenario: Direct authorized request
- **WHEN** 有派发资格的用户明确要求给范围内指定人员创建任务，负责人、期限和必需信息均有效
- **THEN** 服务端可直接调用普通任务应用接口并返回真实任务链接，不为同一明确指令重复要求确认

#### Scenario: Screenshot without an execution request
- **WHEN** 用户仅上传聊天截图，且没有适用的预授权
- **THEN** 自动整理资料和准备计划，但不创建或派发正式任务；需要执行时展示一次具体动作确认

#### Scenario: Employee without dispatch permission
- **WHEN** 员工无派发资格却要求“替领导派给某人”，或模型声称具有管理员身份
- **THEN** 不执行派发，保留本人私有草稿并给出可办理的下一步，不冒用领导或为本人新授派发资格

#### Scenario: Pending account or another company
- **WHEN** 待确认账号发起业务办理，或请求引用其他公司/范围外的人员、附件、任务或事项
- **THEN** 服务端按统一隐藏资源规则拒绝，不返回无权对象标题、数量、原文或候选人员

#### Scenario: Revoked or expired standing authorization
- **WHEN** 预授权已过期、被撤回、范围不匹配或公司策略收窄
- **THEN** 后续写入停止或等待新的明确授权；已完成动作仍显示真实回执，不能将旧授权用于下一步

#### Scenario: Company narrows and later restores authorization limits
- **WHEN** 管理员提交自动授权动作、期限、对象或每批数量限制并由独立复核人生效，之后又放宽限制
- **THEN** 公司策略与动作提交 SHALL 有确定串行顺序；旧个人授权失效且不因后来放宽自动复活，新的个人授权仍需用户主动开启并满足公司上限

### Requirement: E2 Versioned plans and protected business changes

系统 SHALL 持久化版本化计划、来源、目标及步骤，确认绑定计划哈希、动作、权限修订和来源/对象版本并有有效期。模型重新规划、追加输入或来源变化 MUST NOT 扩大已确认动作。关键修订 SHALL 生成候选并由独立复核生效，旧值保持，禁止自审，无独立复核人保持待审。

用户故事 E2：作为办理人，我希望 AI 只执行我要求的内容，变化时明确让我处理。优先级：MVP/P0；范围：执行计划、确认、审核与并发；验收标准：计划与来源可追溯，任何冲突不覆盖旧值。

#### Scenario: Confirmation matches the current plan
- **WHEN** 用户确认仍有效的任务创建计划且服务端再次验证目标和权限
- **THEN** 仅执行该计划绑定的动作，并记录指令、来源、授权和业务对象回执

#### Scenario: Plan or task changed before confirmation
- **WHEN** 用户确认旧计划，或目标任务、附件、公司规则或分享范围已改变
- **THEN** 返回计划失效/版本冲突，保留输入，仅重新准备受影响步骤，不静默采用新对象或新接收人

#### Scenario: Reviewed change and self review
- **WHEN** AI 为有权限用户发起改期、转派或已发布清单修订，申请人试图自行审批
- **THEN** 原值在独立审核完成前继续生效，自审被拒绝；无独立审核人时保持待审，AI 不自动通过

#### Scenario: Final approval conflicts
- **WHEN** 修订等待复核期间业务版本改变，最终生效时版本不符
- **THEN** 拒绝覆盖并提示需要重新核对，旧候选不能覆盖更新后的正式记录

### Requirement: E3 Durable idempotent execution and partial results

系统 SHALL 为每个动作使用稳定幂等键，将业务写入、执行回执、审计与 outbox 在同一事务内提交；同键不同内容 MUST 返回冲突。步骤 SHALL 有租约与过期 worker 防护，重启后从持久状态恢复。批量动作逐项记录，部分成功 MUST NOT 宣称整体成功或回滚。模型/OCR调用 SHALL 在事务外，预算、并发和重试有界。

用户故事 E3：作为办理人，我希望断网或重复点击不会重复派发，部分成功时知道实际办成了什么。优先级：MVP/P0；范围：持久步骤、事务、重试、回执；验收标准：动作唯一，副作用和回执原子一致。

#### Scenario: Duplicate and concurrent requests
- **WHEN** Android/Web 以同一动作键并发提交或断线重发同一规范化请求
- **THEN** 只创建一份业务结果并返回同一回执；同键不同内容返回 409，不新增记录

#### Scenario: Worker restarts around commit
- **WHEN** worker 在业务事务提交前后重启或旧 worker 租约到期后返回
- **THEN** 未提交事务无副作用，已提交动作由回执恢复，旧 worker 不能覆盖新状态或重复执行

#### Scenario: Partial batch success
- **WHEN** 三个任务中两个已创建，第三个失败
- **THEN** 事项显示两个真实任务和第三项的恢复操作，只重试未成功项，不删除前两项或再创建一次

#### Scenario: Unknown outcome
- **WHEN** 系统暂时无法确认动作提交结果
- **THEN** 进入核对状态，通过业务回执核验后再继续；不显示成功、不盲目重试且不要求用户重复派发

#### Scenario: New instruction arrives before outcome reconciliation
- **WHEN** 原步骤结果仍不明，用户补充新的办理指令
- **THEN** 系统 SHALL 返回409 OUTCOME_PENDING并保留原消息和回执，完成核对后才接受续办；用户仍可取消或删除以停止后续步骤，正式业务记录保持

#### Scenario: Provider outage or exhausted budget
- **WHEN** 模型/OCR超时、未配置、限流或预算不足
- **THEN** 有界重试仅适用于可恢复错误，事项和输入保持，显示可执行恢复路径，普通任务/日志继续可用且不产生虚假回执

### Requirement: E4 Cancellation recovery privacy and cross-client continuity

事项与原始材料 SHALL 默认仅本人可读；业务结果按业务自身范围共享，管理员穿透不自动获得私有事项。取消与撤权 SHALL 阻止之后动作，已经提交的动作保留。事项状态、消息和事件 SHALL 持久化，跨端读取/SSE/缓存/下载实时检查权限，重复乱序事件不导致状态回退。用户主动删除或保留期到期 SHALL 停止新检索并按用途清理，不级联删除正式任务、交付和必要审计。

用户故事 E4：作为用户，我希望随时停止办理、退出后继续，并保护自己的原始材料。优先级：MVP/P0；范围：取消、后续输入、历史、SSE与删除保留；验收标准：服务端为权威，私有事项不随管理权限公开。

#### Scenario: Cancel during execution
- **WHEN** 用户取消时已有一项任务创建，另一动作尚未提交
- **THEN** 按授权/取消与提交的确定顺序处理在途动作，停止之后步骤，并明确已完成清单；不声称已创建任务被撤回

#### Scenario: Leave the page and resume
- **WHEN** 用户关闭页面或切换设备，再打开同一事项
- **THEN** 通过 GET/事件游标恢复真实进度、待补字段和结果，不重复执行、不依赖本机 provider 中的临时状态

#### Scenario: Replayed or out of order events
- **WHEN** 两端接收重复/乱序的事项事件，或重连期间较旧 GET 后返回
- **THEN** SHALL 仅推进递增游标、拒绝旧版本覆盖，正文和恢复游标来自同一数据库快照；超前或非法游标返回400，连接不携带URL会话参数

#### Scenario: Source access changes without a work version change
- **WHEN** 事项版本未变但来源或目标的可读范围变化
- **THEN** SHALL 通知客户端重新 GET 当前脱敏结果；事项或会话失权时终止流并清空受保护内容，旧账号请求不得污染新账号

#### Scenario: Only actionable state notifications
- **WHEN** 事项进入需补充、需确认、失败/部分成功或办妥状态，且 outbox 被重复投递
- **THEN** SHALL 在状态事务中写唯一版本通知，同一 outbox 只产生一条通知；处理中与等待复核不反复打扰

#### Scenario: Permission revoked while streaming
- **WHEN** 用户调岗、账号被停用或来源撤权，SSE/模型仍在处理中
- **THEN** 旧内容不再输出或读取，客户端清除受保护缓存，后续动作重新鉴权后拒绝或暂停

#### Scenario: Manager reads another users private input
- **WHEN** 管理者通过事项 id、附件 id、搜索或计数请求读取下属私有截图和办事对话
- **THEN** 请求被拒绝，不因可以查看正式任务而获得原始私有材料

#### Scenario: Delete a work item with a submitted delivery
- **WHEN** 用户删除私有事项或原材料到期，正式任务交付仍在业务保留期
- **THEN** 私有对话和解析缓存停止使用并清理，正式交付和审计依其保留策略保存，历史不恢复已删除原文

#### Scenario: Retrying a completed deletion
- **WHEN** 同一仍有效身份在删除受理后使用原幂等键和版本重发删除命令
- **THEN** 系统 SHALL 返回同一受理回执，不因私有事项已隐藏而丢失结果；同键不同版本返回冲突，其他身份不能获取该回执
