# 月历任务移动发布与回滚

**当前验收目标变化（2026-11-05）**：用户确认恢复每日期最多五行、超过五项为前四项加剩余数量，见 [APP验收D01–D05及C04](app-requirements-acceptance.md)。下文保留完整行版本的历史发布与恢复证据，不作为新折叠要求的验收依据。本批折叠程序和本地复验见[统一验证入口](backend-validation.md)，尚未合并或重新发布。

Issue #58；范围、设计及未完成任务见 [OpenSpec](../openspec/changes/calendar-task-drag-quick-create/tasks.md)。本文件是发布和历史证据的唯一主题入口；以下为已记录结果，文档维护没有重新连接云端或执行部署。

## 最近已记录发布

2026-11-04 20:35（Asia/Shanghai），PR #67合并为`81233ef2621da404614e80f788f756d03c543263`，客户端APK **0.1.5 / 20261108**，SHA256 `bfede00490e3cf4df89ddc03197b1b4a250554986501015230db30443ae79a33`，内部测试签名。构建API为`http://39.96.84.51/api`；本机产物`output/releases/calendar-all-rows/pandora-calendar-fix-0.1.5.apk`。这取代0.1.2/0.1.3/0.1.4记录，不把旧包称为当前包；商店发布签名仍未验收。

该次源码位于服务器`/opt/Grade3_Work-releases/calendar-81233ef/source`，原检出未覆盖。server tree与PR #65相同，后端代码`70f85af`、JAR SHA256 `9bc921368af1dcb7ebf3e00264d27bc48bc3e5eebc706dfa6eb37b71db7b3c43`；仅重启`collaboration-server`，健康UP、CALENDAR_MOVE_ENABLED=true、SCENARIO_DATA_ENABLED=false。V27已应用，无新增迁移。后续整合代码和完整回归另见 [验证入口](backend-validation.md)，不能把本节旧JAR冒充后续整合产物。

发布前后22账号、647任务、2个人事项及任务ID/版本/起止摘要一致，未导入演示数据或修改线上任务；公网33项HTTP检查通过，包含健康/OpenAPI/授权范围、零位移400、旧版本409、员工403、超长范围拒绝。APK下载HTTP200、122975435字节、SHA256一致；Range下载206。证据在`output/releases/calendar-all-rows/`的`deployment.json`、`cloud-http-verification.json`、`download-verification.json`。这些是当时快照，不是当前在线巡检。

## 升级与回滚

1. 备份并核对server Flyway链；V27新增task_reschedule_commands与范围/待审MOVE索引，幂等记录保留期不短于审核。不混用deploy/postgresql，不改既有迁移。
2. 所有task/review消费者兼容MOVE与旧截止候选后，才从CALENDAR_MOVE_ENABLED=false开启能力；客户端按服务端capability显示，不凭本地角色启用。Android用USE_MOCK=false与可访问API_BASE_URL构建。
3. 超时保留原键/原意图，有界前台确认；后台停止重试，退出登录清除账号本机命令，不自动换键重提。监测409/422/429、读写耗时、待审积压与outbox，普通日志不写原因原文、令牌或加密内容。
4. 回滚先关新模式，保留兼容消费者、V27和命令记录；待审MOVE存在时不能回退到忽略MOVE的旧程序。已生效排期以正常新申请纠正，不恢复旧快照抹去新业务。
5. 客户端回退会恢复旧布局限制，不能撤销既有审核。0.1.5下载路由的历史Caddy备份为`/opt/Grade3_Work-backups/calendar-client-81233ef-20261104T123457Z/Caddyfile`；恢复后须validate/reload，无需恢复数据库。仅更新服务器不会替换手机旧APK。

从flutter drive切回release时允许pub刷新原生插件元数据；旧--no-pub可能遗留integration_test注册。不得手改生成注册器或把测试依赖移入生产包，正式APK不传测试token定义。

## 专项证据与限制

以下记录分属不同提交、存在重叠，不合计为一个通过总数。原始失败保留在对应本机output或Git历史。

| 日期/提交 | 已记录证据 | 边界 |
| --- | --- | --- |
| 2026-11-03，基线19db6f3，PR #59 | Docker task/迁移85项、日历专项10项及边界子集退出0；Android跨月改期→待审原位→独立审核→第二客户端/PG读回，空白带日创建；API重启同键回执 | 旧分支迁移V22已由主干V27替代；旧全仓失败不代表当前失败 |
| 2026-11-04，4674f5e→70f85af，PR #65 | 日历59项、两轮Android→HTTP→PostgreSQL；后端专项107/108（时间线断言失败）；部署33项HTTP通过 | 当时全仓未过；后续全仓结果见统一验证入口 |
| 2026-11-04，48556d4，C-08 | 日历69项、受影响23项（重叠）、通知12项；19天任务八次取消及独立审核 | 预览/确认同快照、429冷却；0.1.3已被替代 |
| 2026-11-04，5220e4b，C-09 | 日历76项、通知12项；密集目标跨月移动和独立审核 | 仅三条目标，0.1.4不能证明第四正式行可见 |
| 2026-11-04，60ba430/5175fdd→81233ef | 布局15项、密集7项（重叠）、五条+第六行/十条+第十一行几何验证；Android独立审核后六条正式任务完整展示；分析/APK/strict退出0 | 未重跑完整后端或profile；0.1.5为完整行修复 |

可复现的自动化入口：`scripts/test-backend.ps1`、`scripts/test-flutter.ps1`；真实写入链路必须使用隔离环境，不能刷生产接口制造429。历史机器证据保留在 [原分支JSON](../openspec/changes/calendar-task-drag-quick-create/verification-evidence.json)、[主干整合JSON](../openspec/changes/calendar-task-drag-quick-create/verification-integration-evidence.json)，版本化截图见 [整合预览](images/calendar-task-drag/integration-preview.png)、[待审](images/calendar-task-drag/integration-pending.png)、[带日创建](images/calendar-task-drag/integration-create-prefill.png) 和该change的`evidence/`。截图为合成测试数据，不能替代后续版本验收。

历史profile十次手势成功，但2026-11-03最终233/233帧超过16.7ms，最长57.938ms；慢帧目标未达标。真实手机、TalkBack、完整设备人工矩阵、B/D/E人工确认及非作者审阅缺口保持未完成。2026-11-05自动化全仓通过不关闭这些设备/审阅任务，也不表示本功能可归档。

## 验收步骤

- 公司→月视图检查第四行以后完整可见，拖入已有五条任务的区间占第六行，周增高、后续周下移；取消保留正式五行。
- 从中间日/跨周续段拿起，核对整段高亮与确认起止一致、时长不变；待审保持原位，独立审核后两客户端与PG同版本。
- 同键同内容返回同申请；同键异内容、旧版本、失权、跨公司、零位移、无效落点不覆盖任务。空白长按带日创建仍需确认时间/人员。
- 360/390/412dp、1.0/1.5字体、TalkBack替代操作、减少动画、慢网/后台恢复及60Hz profile矩阵须补实测，不据APK/Mock声称通过。
