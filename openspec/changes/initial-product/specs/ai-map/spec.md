## ADDED Requirements

### Requirement: Actionable work map
AI地图 SHALL 关联目标、重点、任务、日志及风险，手机提供优先行动卡片和图列表切换，Web 支持缩放与过滤；生成建议 MUST 带来源及时间且允许编辑。

#### Scenario: Suggest a task
- **WHEN** 用户从日报生成任务建议
- **THEN** 只生成草稿，确认后才通过正常鉴权接口创建任务

#### Scenario: Choose suggested assignee
- **WHEN** 模型建议负责人
- **THEN** 只能接受当前用户可派发范围内的有效人员，否则拒绝该建议

### Requirement: Server side DeepSeek boundary
DeepSeek SHALL 只由服务端调用，密钥来自环境变量；检索先鉴权，发送最小必要业务文本，排除密码、手机号、私人备注。模型输出 SHALL 校验结构，不能直接执行数据库写入。

#### Scenario: Resist instructions in logs
- **WHEN** 日志内容包含要求读取无权数据或自动派发的指令
- **THEN** 当作业务文本，不扩大检索范围或绕过确认

#### Scenario: Model unavailable
- **WHEN** DeepSeek 超时或额度不足
- **THEN** 保留输入并提供可重试失败状态，基础日志和任务仍可使用
