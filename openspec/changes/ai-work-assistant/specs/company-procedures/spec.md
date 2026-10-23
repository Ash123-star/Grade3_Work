## ADDED Requirements

### Requirement: K1 Published versioned company procedures and templates

系统 SHALL 维护 POLICY、PROCEDURE、TEMPLATE 的不可变版本、维护权限、公司/组织适用范围、有效期、原文及来源、正式发布状态与替代关系。新发布、重要修改与撤回 SHALL 经过现有独立复核，申请人不得自审，无独立复核人保持待审；审核期间旧有效版本继续生效。维护权限 MUST NOT 自动等于全公司读取或跳过审核权限。

用户故事 K1：作为公司资料维护者，我希望维护正式制度和模板，让 AI 按可靠规则办事。优先级：MVP/P0；范围：资料维护、发布、适用范围、生效失效和独立复核；验收标准：未发布与过期资料不当作现行制度。

#### Scenario: Authorized publication
- **WHEN** 有资料维护权限的人提交制度候选且独立复核通过，当前版本和生效时间满足条件
- **THEN** 服务端发布该版本，为适用范围建立受权检索片段，正式规则可作为办理依据

#### Scenario: Self review or no reviewer
- **WHEN** 维护者尝试自行通过，或没有独立审核人
- **THEN** 自审被拒绝或继续待审，不发布新规则，旧版保持有效

#### Scenario: Ordinary upload presented as policy
- **WHEN** 普通员工上传聊天截图/私人文件，或模型声称已学成新制度
- **THEN** 只作为本人办事材料，不自动发布或进入公司正式知识库

#### Scenario: Concurrent revision or scheduled expiry
- **WHEN** 待审候选基于过期版本，或资料到达失效时间
- **THEN** 冲突候选不覆盖新版本，失效资料停止参与新办理；不可用旧版本不因索引延迟继续生效

### Requirement: K2 Authorized grounded answers and evidence invalidation

系统 SHALL 在检索前限制公司、用户范围、发布状态、生效期和适用条件；回答附可打开的标题/版本/位置，优先正式来源，历史案例另行标识为参考。无依据 SHALL 说明未找到，规则冲突 SHALL 暂停依赖该规则的写入并提供可见冲突。来源撤回、失效或权限变化 SHALL 使依赖答案、缓存、检查和未执行计划失效，所有历史引用重新鉴权。

用户故事 K2：作为员工，我希望直接找到适用制度、模板和办理入口，减少到处询问。优先级：MVP/P0；范围：检索、回答、来源、冲突和撤权；验收标准：只使用有效授权资料，不编公司规定。

#### Scenario: Employee asks how to prepare a quotation
- **WHEN** 员工询问报价需要什么材料且存在适用的正式规则
- **THEN** 给出简洁步骤、所需资料、模板入口和依据，允许在同一事项继续准备/办理

#### Scenario: Relevant source occurs beyond the first result page
- **WHEN** 公司有超过50份正式资料且问题对应资料排在默认目录后面
- **THEN** 系统 SHALL 在当前授权集合内按问题和材料检索，返回正文位置与版本，列表提供分页；模型不能引用未提供的资料ID作为依据

#### Scenario: No policy or conflicting policies
- **WHEN** 无有效匹配规则，或同级有效规则互相矛盾
- **THEN** 说明缺少/冲突的具体依据，不从模型常识、相似历史或私人记忆编造统一规定，不执行受影响写入

#### Scenario: Different titles constrain the same obligation
- **WHEN** 同范围不同标题的有效资料对相同材料或数值给出不一致约束，或已准备的计划之后新增冲突依据
- **THEN** 系统 SHALL 展示双方可读版本和原文位置，暂停依赖写入并使旧确认失效；无法证明重叠约束兼容时交由维护人核对，不让模型任选一份

#### Scenario: Another department or private draft
- **WHEN** 用户查询无权部门模板、未发布制度、他人私人备注或未提交日报
- **THEN** 检索、计数、摘要和下载均不泄漏该内容，不以全局召回后隐藏标题替代范围隔离

#### Scenario: Source revoked after an answer
- **WHEN** 回答后制度被撤回、用户调岗或模板权限被收回
- **THEN** 后续读取引用及执行均重新校验，依赖旧资料的结果停止使用，已发生业务仅保留合法审计

### Requirement: K3 Declarative supported procedures with truthful outcomes

系统 SHALL 使用经发布审核的声明式流程定义，只映射已接入的任务创建、反馈与关键修订申请等白名单能力；字段、目标和审核人仍由业务模块验证。流程 MUST NOT 包含任意 SQL、脚本、URL 工具或权限提升。用户指令允许且信息齐全时可自动续办，否则仅准备材料并说明缺少条件。未接入的报销/采购等业务 MUST NOT 被描述为已提交。

用户故事 K3：作为员工，我希望找到流程后 AI 能继续帮我准备和办理，而不只给一段解释。优先级：MVP/P0；范围：已接入动作目录、字段预填、模板与审批衔接；验收标准：每个“已办理”都有业务回执，未接入明确停点。

#### Scenario: Supported workflow from query to action
- **WHEN** 用户要求“按报价流程给李明建任务”，制度有效、人员和期限明确且用户有派发权限
- **THEN** 自动找到模板并补充明确清单，经普通派发应用接口创建任务，返回依据及真实任务链接

#### Scenario: Unsupported external procedure
- **WHEN** 用户要求提交尚未接入的采购或报销流程
- **THEN** 可整理材料、查找模板和合法入口，明确仍需在对应系统提交，不生成假审批号或发送结果

#### Scenario: Template tries to change identity or review chain
- **WHEN** 流程定义或文件要求以领导身份执行、指定非法审核人或绕过版本校验
- **THEN** 拒绝非法映射，保留可安全准备的材料，不创建越权申请或更改审核策略

#### Scenario: Android and Web use the same rules
- **WHEN** 两端以同一用户/版本查询或提交同一流程
- **THEN** 服务端返回相同资料范围、权限、版本/幂等条件与错误状态；旧版 Web 未提供新界面时不能宣称已支持自动办事 UI
