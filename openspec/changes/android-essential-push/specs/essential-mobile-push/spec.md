## ADDED Requirements

### Requirement: Essential event selection
Should，范围为必要任务/截止/审批/入职事件；系统 SHALL 使用阿里云移动推送，非短信。仅生效的新派发/转派、关键变更、撤回、成果退回、截止/逾期、本人待审批/改派/驳回和本人入职审核结果允许入队，普通审批通过、评论、日志、AI MUST NOT 推送。

#### Scenario: Relevant business event
- **WHEN** 业务事务成功且事件在白名单内
- **THEN** 站内消息与推送投递 SHALL 同事务持久化，重复事件/设备绑定只排队一次

#### Scenario: Rejected candidate or irrelevant event
- **WHEN** 修改尚待审核、事务回滚或事件不在白名单
- **THEN** 系统 MUST NOT 发出对应业务变更的锁屏通知

### Requirement: Device and session isolation
MVP，范围为本人Android设备。设备绑定 SHALL 从认证会话取得公司和接收人，并生成绑定lease；发送前 MUST 验证绑定、会话和当前权限。待确认用户仅允许设备/偏好及本人入职结果，不得获取公司业务数据。现有审批权限和禁止自审规则保持。

#### Scenario: Switch accounts or revoke session
- **WHEN** 同一设备切换账号、退出、改密或账号停用
- **THEN** 旧绑定投递 SHALL 取消或因会话失效被跳过，旧点击不能打开新账号数据，系统已展示通知在客户端恢复/退出时清除

#### Scenario: Invalid device or foreign object
- **WHEN** 请求提交非法设备标识、伪造接收人或打开他人/他司通知
- **THEN** 服务端 SHALL 拒绝且不产生部分绑定或返回目标资料

### Requirement: Durable and bounded delivery
Should，范围为云投递。系统 SHALL 保留站内可用性，独立进行限次重试、过期与去重，区分供应商受理和设备送达；未配置不得发请求或声称成功。锁屏内容 MUST 为通用摘要，不含任务正文、个人信息、审批原因或凭据。

#### Scenario: Temporary provider failure
- **WHEN** 供应商超时或可重试错误
- **THEN** 系统 SHALL 持久化退避时间，最多5次；站内消息不受影响，不记录密钥或敏感正文

#### Scenario: Stale or permanent failure
- **WHEN** 当前版本/审核人/权限已变化、事件过期、设备失效或达到重试上限
- **THEN** 投递 SHALL 取消或终止，不继续推送过时内容

### Requirement: Deadline stages
Should，范围为任务真实参与人。系统 SHALL 对未完成DISPATCHED/RECEIVED任务在提前24h/1h及逾期生成分阶段提醒，键含deadline和接收人，不补发已错过的阶段。

#### Scenario: Multiple participants and repeated scheduler
- **WHEN** 任务到达提醒窗口且有多名参与人，调度重复运行
- **THEN** 每位有效参与人 SHALL 每阶段只产生一条，接收/反馈等文案不得代替真实状态

#### Scenario: Changed or completed task
- **WHEN** 任务改期、完成、撤回、归档或错过阶段窗口
- **THEN** 旧阶段 MUST NOT 继续发送或在恢复时补发

### Requirement: User settings and safe navigation
Should，范围为Android。设置 SHALL 提供总开关、任务/截止/审批分类、上海免打扰和系统权限状态；关闭某类不影响站内消息。Android13 SHALL 在用户开启时申请权限，拒绝后保留站内可用。通知点击 SHALL 支持前后台和冷启动，并经服务端重新鉴权后白名单跳转，不把供应商extras当授权。

#### Scenario: Enable and open
- **WHEN** 用户配置可用并授权开启，随后点击属于当前绑定的有效通知
- **THEN** 手机 SHALL 注册设备并同步本人设置；身份恢复后进入对应授权详情，SSE不得重复创建系统通知

#### Scenario: SDK channel process cold start
- **WHEN** 用户已经同意开启通知后，SDK独立channel进程或应用主进程冷启动
- **THEN** 自定义Application SHALL 在主线程按已持久化同意标记及应用配置初始化SDK；设备和厂商注册仍须经过现有开启状态、服务端配置和系统权限门控，缺配置或未同意时MUST NOT 初始化或注册

#### Scenario: Disable and re-enable in one process
- **WHEN** 用户关闭通知后在同一应用进程再次授权开启
- **THEN** 客户端 SHALL 清除关闭时的本机同意标记并在重新开启时再次保存，保留原设备绑定和授权点击规则，不因SDK已初始化而跳过同意恢复

#### Scenario: Quiet hours or denied permission
- **WHEN** 当前处于免打扰、分类关闭或系统拒绝通知权限
- **THEN** 系统 SHALL 延后并重新校验有效期或取消对应推送，不影响站内功能；设置如实显示状态

#### Scenario: Missing configuration or expired notification
- **WHEN** 阿里云配置缺失或冷启动点击已失效/属于旧绑定的通知
- **THEN** 客户端 MUST NOT 假报开启或直接展示敏感详情，并提供明确的状态或失效提示
