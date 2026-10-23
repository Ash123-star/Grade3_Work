## ADDED Requirements

### Requirement: U1 One workbench organized around the users work

AI 地图 SHALL 使用一个统一办事工作台，支持文字、主动选择图片/文件与任务上下文；按需要处理、正在办理、最近办过组织真实事项，同一事项可追加材料。输入区 SHALL 位于五栏导航之上，兼容键盘和安全区；主导航仍为导图、视图、日志、AI地图、我的，默认导图。新首页 MUST NOT 保留三个分析 Tab、“开始分析”、脑图标、范围横幅、日期筛选、用量/重置、旧欢迎大卡或优先三件事。

用户故事 U1：作为用户，我希望直接说事或提供截图，看到事情办到哪里，而不必先学习三种 AI 功能。优先级：MVP/P0；范围：Android AI 主入口、输入、事项、详情与续办；验收标准：单入口完成三条链路，导航和权限保持。

#### Scenario: Start without choosing a feature
- **WHEN** 用户在 AI 地图输入“按截图给李明建任务”并选择图片
- **THEN** 在同一事项内展示材料、必要追问、真实办理结果和任务入口，不强制先进入“截图转任务”功能页

#### Scenario: Empty workbench
- **WHEN** 用户尚无事项
- **THEN** 展示一句自然邀请、小幅既有角色及“截图建任务、检查交付、找制度和模板”等可编辑示例，不显示虚构事项或大段能力说明

#### Scenario: Missing fields and later continuation
- **WHEN** 任务缺少人员/期限，用户离开后重新进入
- **THEN** 一张补充卡只列必要字段，选择器限定授权范围，保留已知信息和输入焦点，从服务端恢复后可继续

#### Scenario: Keyboard and long content
- **WHEN** 用户在360dp屏幕或1.5倍字体下展开多行输入、预览多个附件并弹出键盘
- **THEN** 输入区及主操作可达，列表末项有避让，五栏在键盘关闭后顺序恢复，不遮挡、不横向溢出、不通过缩小文字解决

### Requirement: U2 Product copy truthful outcomes and useful recovery

界面 SHALL 使用简短、具体、面向用户动作的中文，并复用设计第10节的语义。正式任务创建、草稿、检查通过、反馈已提交和最终验收 MUST 明确区分。确认卡 SHALL 写清对象、接收人、期限和分享材料；错误 SHALL 保留输入并提供可行恢复路径。页面 MUST NOT 常驻显示开发术语、内部状态枚举、原始异常、traceId、架构解释或无助于决策的小字；必要的未核实项、范围影响和演示环境标识不得隐藏。

用户故事 U2：作为用户，我希望一眼看懂结果和下一步，不在工作界面阅读开发说明。优先级：MVP/P0；范围：全部 AI 状态、结果、确认、失败及相关弹层文案；验收标准：文案对应真实行为，关键业务事实不被小字或装饰隐藏。

#### Scenario: Created task and submitted delivery
- **WHEN** 服务端分别返回任务创建成功和反馈提交成功回执
- **THEN** 分别显示“任务已交给李明”和“已提交，等待验收”及对应入口，不将创建任务说成工作已完成

#### Scenario: Action confirmation
- **WHEN** 当前动作没有明确指令或适用预授权，需要用户确认
- **THEN** 用“创建任务”“提交反馈”等具体动作作主按钮，展示实际影响，不把计划哈希、API或执行器状态当成用户说明

#### Scenario: Check cannot verify or only partly succeeds
- **WHEN** 材料缺失、数字矛盾、签字无法验证或批量动作部分失败
- **THEN** 明确指出缺什么、哪里矛盾或哪些已办成，提供补传/继续处理；不显示含糊成功、不用低对比小字掩盖未完成

#### Scenario: Finished check still requires corrections
- **WHEN** 检查动作已经完成但报告为NEEDS_FIX、UNVERIFIABLE或STALE
- **THEN** 两端 SHALL 按报告显示需要补充材料、需核对或重新检查，不能只因事项SUCCEEDED就显示已办妥；任务创建和反馈提交分别使用真实业务回执文案

#### Scenario: Service failure offline or no permission
- **WHEN** 网络/模型失败、离线或权限不足
- **THEN** 给出与情况一致的简洁提示、保留合法输入和重试/返回等入口，不展示供应商原始报错，不承诺已同步或已执行

#### Scenario: Invalid or incompatible work response
- **WHEN** 服务返回未知事项状态、不兼容契约、缺少身份/版本或损坏的消息/回执结构
- **THEN** 客户端 SHALL 显示可恢复错误且保留合法输入，不用默认“已办妥”或空列表代替失败，不消费为新的成功回执

#### Scenario: Retry and conflict during continuation
- **WHEN** 补充或命令断线重发，或事项已被另一端更新
- **THEN** 相同未确认请求 SHALL 保留请求键；请求动作、版本或选定对象改变后换键，冲突时重新读取并保留输入；消息与确认/取消/续办不得并发提交旧版本

#### Scenario: Paginated work history refresh
- **WHEN** 用户展开更多历史后刷新，或分页期间另一端更新事项导致页间重复
- **THEN** Web SHALL 按服务端nextCursor重新读取已展开页、按身份合并且保留较新版本；分页响应失败或游标未推进时保留既有历史并提示重试，不能把失败显示为空历史

#### Scenario: Invalid deletion acknowledgement and non JSON denial
- **WHEN** 删除响应的身份/停止状态不匹配，或鉴权拒绝没有JSON正文
- **THEN** Web SHALL 不把无效删除回执消费为成功；401/403/404仍清空受保护正文与输入，不依赖错误正文格式才能处理失权

#### Scenario: Unsupported business
- **WHEN** 请求涉及尚未接入的外部系统
- **THEN** 清楚展示已整理的材料及还需去哪里提交，不把“材料已整理”写成“办理成功”

### Requirement: U3 Existing visual language meaningful motion and accessible continuity

客户端 SHALL 复用当前 SunnyPaperTokens/PaperSurface、奶油底、薄荷/浅紫语义色、圆角卡片、本地字体与现有合法素材，不引入新视觉体系。动效 SHALL 仅服务于真实的上传、状态变化、展开和完成；按压100–160ms、页面/弹层160–220ms、卡片状态180–240ms、真实完成一次250–350ms，并集中管理token。系统减少动画时 MUST 停止循环/缩放/大位移，静态文字、按钮和语义完整。触控≥48dp，普通正文对比≥4.5:1，关键错误/结果使用正常可读字号。

用户故事 U3：作为用户，我希望新 AI 页与当前应用一致，过程流畅且在大字体、读屏或关闭动画时仍易用。优先级：Android体验与共享契约MVP/P0，Web新页面Should/P1；范围：样式、动效、无障碍、跨端状态；验收标准：遵循当前团团token与设计第10/11节量化标准。

#### Scenario: Real progress and success
- **WHEN** 附件上传、步骤开始和业务事务真实完成
- **THEN** 依次用缩略图/真实进度、局部处理指示和一次完成反馈呈现，不伪造百分比、思考过程或提前庆祝

#### Scenario: Reduced motion and assistive technology
- **WHEN** 用户启用减少动态效果、TalkBack或字体放大
- **THEN** 动画降级但业务语义完整，读屏只在阶段变化时播报一次，焦点保持，内容换行而非截断主操作

#### Scenario: Offline decoration or asset failure
- **WHEN** 离线、素材缺失或解码失败
- **THEN** 代码表面、文字、交互和状态仍完整，装饰不拦截触摸，不能以图片占位冒充真实结果

#### Scenario: Device changes and new Web workbench
- **WHEN** 用户在另一端恢复事项，或P1 Web新工作台交付
- **THEN** 使用同一服务端版本、状态/错误和授权契约；Web可使用桌面布局但保留相同确认与真实结果语义，P1未交付前明确其UI范围尚未完成

#### Scenario: Smooth card transitions under load
- **WHEN** 在验收记录的代表机型profile模式滚动和切换处理卡
- **THEN** 保持滚动锚点、不逐token刷新整页，按设计目标记录帧耗时及是否达标，离屏/后台暂停装饰，不用模拟器截图宣称性能通过
