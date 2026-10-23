## ADDED Requirements

### Requirement: D1 Versioned acceptance criteria and grounded checks

系统 SHALL 将明确要求和有效公司规则转换成版本化交付清单，区分已核实与推断条目。检查 SHALL 绑定任务、清单、规则、附件哈希和解析/检查器版本，逐项给出 PASS、NEEDS_FIX、UNVERIFIABLE 或 NOT_APPLICABLE 及定位。必须项全部可核实通过才可整体 PASS；不适用须有依据。已发布清单关键修改 SHALL 走独立复核，旧版继续生效。

用户故事 D1：作为交付人，我希望提交前自动找出缺材料和前后矛盾，减少退回重做。优先级：MVP/P0；范围：任务清单、文件检查与可定位问题；验收标准：依据有效、结果能复核，主观推断不成为强制验收条件。

#### Scenario: All objective requirements satisfied
- **WHEN** 任务要求的报价单、成本明细齐全，结构化客户/数量/日期及金额字段按明确口径一致
- **THEN** 对可核实必须项给出通过和证据，语义建议另列，不把检查通过称为正式验收通过

#### Scenario: Missing material or numeric contradiction
- **WHEN** 缺少要求的成本明细，或任务数量20而文件数量18
- **THEN** 明确标出缺失材料和两处依据，提供补传/补充说明，不只返回分数或泛泛改进建议

#### Scenario: Legacy task has no checklist
- **WHEN** 旧任务没有明确清单或验收要求
- **THEN** 可做已知内容初检但标明无法核实完整要求，不生成推断硬条件或宣称完整验收条件已满足

#### Scenario: Criteria changed during review
- **WHEN** 有权人申请修改已发布清单且复核尚未通过
- **THEN** 检查继续使用当前有效旧版；禁止自审，通过时仍检验业务版本，过期候选不能覆盖新要求

### Requirement: D2 Honest uncertainty and evidence repair

系统 SHALL 把无证据、模糊 OCR、不能验证的公式、签字真伪及来源冲突标为无法核实，而非默认通过或不适用。金额核对 MUST 使用明确币种、单位、精度和舍入规则；不能凭模型推断更改业务数值。补传或修改材料 SHALL 生成新检查版本，旧报告仅供历史查看。首期 MUST NOT 自动改写原文件。

用户故事 D2：作为交付人，我希望 AI 说清哪里看不准，并允许补材料继续。优先级：MVP/P0；范围：无法解析、语义判断、公式/签字、复检；验收标准：不漏检冒充通过，错误修正不修改原文件。

#### Scenario: Unsupported signature or formula proof
- **WHEN** 必须项需要验证签字真实性或复杂公式结果，而当前能力无法验证
- **THEN** 标为需要人工确认，给出对应位置及原因，不用模型置信度替代核验

#### Scenario: Damaged file or incomplete OCR
- **WHEN** 必须材料损坏、加密或部分页提取失败
- **THEN** 整体不显示通过，保留已完成检查和原请求，支持替换文件或转人工核对

#### Scenario: Currency or unit mismatch
- **WHEN** 对比字段使用不同币种/单位或缺少换算依据
- **THEN** 不直接求和或判定一致，要求提供明确口径，不私自调整数值

#### Scenario: User repairs the evidence
- **WHEN** 用户上传修正版并补充明确说明
- **THEN** 对新哈希重新检查，清楚展示最新结果，旧通过报告不能用于新文件自动提交

### Requirement: D3 Authorized submission after checks with human acceptance

系统 SHALL 仅在检查通过且用户明确要求提交或具有匹配预授权时自动提交。提交 MUST 重新验证当前参与角色、状态、任务/清单/规则版本和附件哈希，在单事务中创建 FEEDBACK、交付引用、审计及回执。纯检查不提交，检查不通过或无法核实时不自动提交。用户主动选择人工核对模式 SHALL 留下非通过报告与原因，不得绕过业务硬约束。AI MUST NOT 自动接收、验收、归档或审批。

用户故事 D3：作为任务参与人，我希望说“检查后提交”后系统完成检查和反馈，等待有权人验收。优先级：MVP/P0；范围：检查到任务反馈/交付附件的事务闭环；验收标准：权限和版本再次验证，无隐含接收或自动验收。

#### Scenario: Check and submit explicitly requested
- **WHEN** 合法参与人已满足任务当前阶段要求，明确要求“检查后提交”，所有必须项通过且版本未变
- **THEN** 只提交一次反馈和允许共享的交付附件，显示“已提交，等待验收”，由原有合法验收人决定最终结果

#### Scenario: Check only
- **WHEN** 用户只要求“帮我检查这份文件”
- **THEN** 返回检查结果，不提交反馈、不发起审批、不改变任务阶段

#### Scenario: Check only with a submission authorization
- **WHEN** 用户已有任务内提交授权，但本次只要求检查，或自动写入开关已关闭
- **THEN** 纯检查仍可运行，模型提交建议不能覆盖本次只检查要求；写入开关关闭继续阻止正式反馈，不影响私人检查报告

#### Scenario: Current instruction prohibits a previously authorized submission
- **WHEN** 用户在已有长期提交授权时明确说“先不要提交这份材料”，模型仍返回提交候选
- **THEN** 服务端不生成可执行提交步骤，保留材料并等待下一步要求，长期授权不能覆盖本次禁止指令

#### Scenario: Stale report or concurrent edit
- **WHEN** 检查后任务、清单、制度或材料改变，或两端同时提交相同交付
- **THEN** 旧检查不能自动用于提交；冲突保留材料，重试按稳定键去重，不产生重复反馈

#### Scenario: Not received or unauthorized actor
- **WHEN** 任务尚未接收，或有阅读权的上级并非当前反馈参与人
- **THEN** 按任务状态机/操作权限拒绝自动反馈，给出合法下一步，不隐含接收、不因可读而代提交

#### Scenario: Manual review of unverifiable evidence
- **WHEN** 用户主动选择“提交人工核对”并确认未核实项目和说明，且不存在业务硬约束阻止
- **THEN** 按合法反馈权限记录手工核对模式、非通过报告与附件，明确等待人工处理，不改成检查通过或已验收

#### Scenario: Business feedback transaction fails
- **WHEN** 写反馈、交付绑定、回执或 outbox 的任一步发生事务异常
- **THEN** 整个提交回滚，任务和附件关联不半生效，检查结果仍可查看，重试不重复创建
