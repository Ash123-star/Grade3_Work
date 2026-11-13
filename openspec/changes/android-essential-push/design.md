## Context
当前 MessageApplicationService 把 outbox 写入站内消息，SSE 仅前台启用；Android尚无通知权限/设备SDK。基线31f2df2，Issue #86。用户明确改选阿里云移动推送，非短信。SDK依据官方文档 https://help.aliyun.com/document_detail/434552.html 和 aliyun_push 1.2.0 包接口；服务端采用官方 aliyun-java-sdk-push。

## Goals / Non-Goals
目标为必要事件的可靠投递、设备会话隔离、本人设置和安全跳转；外部云配置可开关。非目标见proposal；不保证系统强制停止、用户关闭通知时强行送达，不把供应商接收等同设备送达。

## Decisions
1. 阿里云聚合厂商通道优于自建常驻连接或逐家SDK：国内后台可达性更合适且维护量较小；用户已指定阿里云。采用官方Flutter插件和Java SDK，避免自写签名。RAM/STS只放服务端；客户端SDK AppKey/AppSecret为EMAS应用标识配置，不是RAM访问密钥，不记录日志。没有配置不初始化/不发云请求。
2. 复用outbox。站内写入与push_deliveries入队在同一事务；定时worker独立投递，站内可用不依赖供应商。push_devices以云deviceId唯一，绑定当前session_hash与随机binding lease；换号原pending投递因lease/session不符取消。投递唯一键为通知/设备/lease，状态PENDING、ACCEPTED（供应商受理）、CANCELLED、FAILED。数据库行锁SKIP LOCKED防并发重复；超时后可能供应商已受理，通过稳定通知ID覆盖同类和客户端不重复展示缓解，不声称跨网络exactly-once。
3. 本人API：PUT/DELETE /push/device（SDK deviceId），GET/PUT /push/preferences（enabled、tasks、deadlines、reviews、quietEnabled、quietStart/quietEnd上海小时、version），GET /push/open/{notificationId} 返回重新授权后的route和objectId。客户端不得指定user/company。设备绑定需当前会话；PENDING仅绑定和本人入职申请结果，不能读取任务。注销/改密撤销session后发送端立即失效，客户端清空系统通知。设置乐观版本避免跨设备覆盖。
4. 新迁移（以当前最大版本后追加，实施时核对远端）创建设备、偏好、投递表及截止索引，无历史消息补推；设备30天不更新过期，投递仅保留30天诊断状态并定期清理。RPC供应商HTTP超时5秒、最多5次、指数退避，过期/权限变化不重试；无设备不补推历史。系统关闭通知/分类关闭直接取消待发送，免打扰延至上海结束时刻并重新检查expiry。
5. 事件白名单：TASK_ASSIGNED（新参与人）、TASK_REVISED/REASSIGNED/RESCHEDULED、TASK_EVENT内WITHDRAWN/RETURNED、REVIEW_PENDING/REJECTED、MEMBERSHIP的APPROVED/REJECTED。普通接收/反馈/验收/评论/日志/AI不推。TASK_EVENT补不可变action与版本；推送快照版本与当前版本不一致取消，避免旧审批/旧任务提醒。发送前调用实际任务/审核应用读取校验当前组织范围及审核步骤，取消已失效待办；锁屏和厂商渠道统一只发无业务正文的摘要。
6. 截止scheduler依真实任务deadline对所有参与人处理，仅DISPATCHED/RECEIVED：24h和1h窄时间窗、不补错过的阶段，逾期一次；键含deadline/阶段/接收人。DAY过期在deadline-1h，HOUR在deadline，OVERDUE在deadline+24h；完成/撤回/改期使旧投递无效。站内也保留这些阶段数据，不从文案推断。
7. Android三类channel，SDK只由用户在通知设置开启后初始化（首次需授权）；设置页有系统通知状态、总开关/分类/免打扰。插件负责系统通知，SSE只刷新不再创建本地通知。native channel负责Android13权限、冷启动点击缓存及channel锁屏private；SDK通知extras仅notificationId、binding，不含正文。前后台点击等待身份可用，binding不匹配丢弃，调用open API后使用白名单路径跳转；PENDING跳本人申请状态页刷新。

实施补充：官方Flutter插件initPush强制开启DEBUG，故通过原生桥接初始化同一官方Android SDK并在注册前LOG_OFF，复用官方厂商注册工具；SDK负责系统通知展示，Dart不重复创建通知。云投递使用独立调度器，避免网络等待阻塞站内消息调度。REVIEW_PENDING携带不可变reviewStepId，审核改派后旧步骤提醒失效；新参与人已生成TASK_ASSIGNED时不重复生成该次修订提醒。OPPO使用官方消息分类参数，其余厂商按支持的通道字段映射。

## Risks / Trade-offs
- 云应用/厂商证书、正式签名和RAM权限未提供 → 默认关闭，受控供应商测试，真实设备任务保持未完成。
- Android已显示的通知无法服务端即时撤销 → 打开/恢复/退出时清除系统通知，点击再鉴权；过时详情不泄露。
- SDK引入包体及原生依赖 → 集中编译验证；不调整本分支既有素材打包配置，OSS迁移/剥离的验收依赖原资源主题；未配置不启动SDK采集。
- 事务内有短网络调用 → 每次限制处理数量，设置5秒超时并SKIP LOCKED；只影响推送worker不影响业务事务。

## Migration Plan
先应用新增Flyway并部署默认关闭后端，再构建带EMAS应用标识/厂商配置的APK。核对云端配置后打开服务端PUSH_ENABLED，再由用户授权开启并绑定设备；验证成功再扩大。回滚关闭PUSH_ENABLED和App开关，保留新增表及投递审计，不删除已发布迁移。只保存设备标识和供应商受理ID，不保存敏感通知正文。

## Open Questions
阿里云EMAS Android应用、RAM/STS、厂商通道及正式签名需要用户在安全环境配置；不影响可独立验证的代码实施，但阻塞云端真实送达验收。不存在有效配置时设置页如实显示未配置，不显示“已开启推送”。
