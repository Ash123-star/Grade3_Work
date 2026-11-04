# 月历任务移动发布与回滚

关联 Issue #58，OpenSpec `calendar-task-drag-quick-create`。

1. 备份并按现有 server Flyway 链升级到 V27，不混用 deploy/postgresql。V27 新增 `task_reschedule_commands`、待审 MOVE 查询索引与范围索引；不改既有迁移。幂等表有公司一致的用户/任务/审核外键，保留期不短于审核；无超时清理任务。
2. 全部 task/review 实例先部署能消费 MOVE 与旧截止候选的版本；保持 `CALENDAR_MOVE_ENABLED=false`。全部消费者兼容后再打开。客户端通过服务端 capability 保守显示，不能凭本地角色自行启用。
3. Android 使用 `--dart-define=USE_MOCK=false` 和可访问的 `--dart-define=API_BASE_URL=...` 构建。长按拿起任务，抓取中间日保留锚点，边缘停留跨月；确认后待审原位，独立审核后刷新。空白长按创建带日，不默认具体时间/人员。
4. 超时只能显示结果待确认，并保留加密存储中的原键/原意图。确认有界且切后台停止重试。退出登录清除该账号本机移动命令，不能自动换键重提。
5. 监测 409 各业务错误、422 范围密度、读写耗时、待审积压及 outbox。原因、访问令牌和本机加密内容不写普通日志。
6. 回滚先关闭新模式并保留兼容消费者，保留 V27 和命令记录。若有待审 MOVE，禁止回退到忽略 MOVE 的旧审核程序；先暂停审核或处理兼容。已生效排期只通过新的正常申请纠正，不恢复旧数据库快照。

## 验收步骤

- 管理者在公司月历，长按多日任务中间一天拖到另一月；确认新起止和原因，记录原键/审核 ID。待审时日历和数据库仍为原值。
- 独立审核人通过；原/新月、当天清单、详情/列表和第二 HTTP 客户端读到同一版本，新事件/outbox 各一次。
- 原键同内容返回同申请；同键不同内容、同版本两键争抢、版本变化、失权和跨公司均不得覆盖任务。
- 空白或部分占用日期剩余空白长按进入表单；明确选时间/人员，检查创建待审及通过后月历。取消、空白原因、非法日期和无效落点无写入。
- 设备记录 360/390/412dp、1.0/1.5 字号、TalkBack 替代操作、减少动画、慢网/断网/后台恢复及 60Hz profile 十次跨月拖动。未实测项留在验证报告，不能据 APK/Mock 宣称通过。

## 本机验收产物（2026-11-03）

HTTP release 模式 APK 位于 mobile/build/app/outputs/flutter-apk/app-release.apk，122909455 bytes，SHA256 338590B39EF4412C8A2FDC0CEC65CB8F78DAB332CEB1DB2DC8FEF1B451888F83。命令为 flutter build apk --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:18088/api，入口 lib/main.dart，不传任何测试 token defines。该地址仅用于 Android 模拟器访问宿主机本任务 Docker；现有 debug signingConfig 只供内部联调，不能当商店发布签名。

从 flutter drive 切回 release 时不要跳过插件元数据刷新：本次直接 --no-pub 构建曾留下 integration_test 注册引用而失败，正常 flutter build（允许 pub 阶段）重新生成注册后退出 0。不手改 GeneratedPluginRegistrant.java，不把 integration_test 移为生产依赖。

真实跨月改期/独立审批/快捷创建链路、Docker 范围专项、最终 Flutter 分析及 OpenSpec strict 已通过。全仓仍有失败；模拟器 10 次 profile 手势成功但 最终 233/233 帧超过 16.7ms，性能目标未达到，TalkBack/完整人工矩阵与跨组确认/审阅未完成。默认新模式保持关闭；按用户 2026-11-03 明确授权已推送[草稿 PR #59](https://github.com/Ash123-star/Grade3_Work/pull/59)并发布[中文工作清单评论](https://github.com/Ash123-star/Grade3_Work/pull/59#issuecomment-6596996618)，尚不满足合并/上线/归档门槛；全部证据与未完成项见 openspec/changes/calendar-task-drag-quick-create/verification.md。


2026-11-04 主干整合使用 V27，与已发布 V22/V23/V26 并存；审核消费者沿用当前直属单级审核及创始人权限内免审。上面的 2026-11-03 验收和 APK 只属于旧分支。本轮结果见 `openspec/changes/calendar-task-drag-quick-create/verification-integration.md`。

实现阶段 APK：`output/releases/calendar-drag-integration/pandora-calendar-drag.apk`，SHA256 `2A972561801DC0CEAF0990B8EB424B0C1157444C8F0A49B22F56393C96D872BA`，当时尚未部署服务器。该旧产物已由以下 0.1.2 包替代。日历 59 项、两轮 Android 本地真实链路、分析和打包通过；全仓与性能门槛仍未通过。

## 当前线上发布（2026-11-04 15:46，Asia/Shanghai）

用户明确要求合并部署后，PR #65 已合并为 `70f85af`，39.96.84.51 的单一后端实例先升级 V27／MOVE 消费者，再开启 `CALENDAR_MOVE_ENABLED=true` 并重启。33 项线上 HTTP 检查通过，原 22 个账号、647 条任务、2 条个人事项及任务日期／版本不变。源码检出中的用户改动保持原样。

当前测试 APK：`output/releases/calendar-drag-70f85af/pandora-calendar-drag-0.1.2.apk`，versionCode `20261105`，SHA256 `7C23AA1EB0871D0AD944A4C86B20FBAD73FC6E0B7265014F60D2FAE747E83B31`；签名与此前 0.1.1 相同，可以覆盖安装。真实 API 为 `http://39.96.84.51/api`。

服务器备份、分阶段启动、验证、已知限制及上线后回滚要求见 [部署记录](../openspec/changes/calendar-task-drag-quick-create/deployment-20261104.md)。发布依照用户明确指令进行；全仓、性能、实机及审阅缺口仍保留，不能把部署结果当作全量验收完成。
