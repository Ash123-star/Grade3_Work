# 月历拖动部署记录（2026-11-04）

用户在获知全仓失败、模拟器性能未达标及非作者审阅未完成后，明确要求“合并，并部署”。按本次发布指令执行；该决定不表示既有验收缺口已修复，也不将 7.4、实机／TalkBack 或归档任务勾选为完成。发布指令和限制已保留于 [PR #65 评论](https://github.com/Ash123-star/Grade3_Work/pull/65#issuecomment-6625409430)。

## 已发布版本

- [PR #65](https://github.com/Ash123-star/Grade3_Work/pull/65) 已合并到 `main`；合并提交 `70f85af21c10772b097ebebfd10372fe68e4888c`，本机已拉取。
- 服务器 `39.96.84.51`，原 `collaboration-server` systemd 服务；仅发现一个任务／审核后端实例，全部消费者随同一 JAR 升级。
- 后端从该合并提交归档的源码重新构建，Maven package 退出 0。JAR SHA256：`9bc921368af1dcb7ebf3e00264d27bc48bc3e5eebc706dfa6eb37b71db7b3c43`。
- 2026-11-04 **15:46:42（Asia/Shanghai）**部署完成。PID 由 `1558826` 变为 `1640832`，健康接口返回 `UP`。
- 实际数据库仍为 `workpanel_annual2026`，V1–V23／V26 共 24 个已发布迁移与新 JAR 逐字节一致；仅新增 V27，Flyway 无失败迁移。
- 第一阶段关闭移动能力启动新后端，验证迁移和 MOVE 消费者；第二阶段开启能力并再次重启。`/etc/collaboration-calendar.env` 持久设置 `CALENDAR_MOVE_ENABLED=true`，由 `zzzzz-calendar.conf` 的 `EnvironmentFile` 加载。
- 保持 `SCENARIO_DATA_ENABLED=false`。部署前后均为 **22 个账号、647 条任务、2 条个人事项**；全部任务的 ID／版本／起止日期摘要一致，没有重置业务数据。
- 服务器源码检出已有部署配置和备份文件，未覆盖、重置或提交；仅替换运行 JAR。运行版本记录位于 `/opt/Grade3_Work/server/target/deployment-calendar.json`。

## 线上核验

- 从公网 API 执行 33 项 HTTP 检查（包括退出临时会话）：健康、运行时 OpenAPI、四个已有测试账号登录、月历范围／快照／排期约束、`ownerId` 参与人过滤兼容、任务看板、个人事项月历、详情能力、非法零位移、版本冲突、员工越权和超长范围拒绝。
- 当前月份查询返回的可移动任务数量：`boss` 34，`admin` 本次前 100 条中有 100 条；普通员工 `zhou`／`zhao` 均为 0，未扩大改期权限。计数为验证时的查询结果，不是固定产品配置。
- 非法零位移返回 400、过期版本返回 409、员工改期返回 403；拒绝请求未改变任务版本或排期。没有在真实业务任务上提交成功改期申请；正向改期与独立审核链路已有两轮本机 Android→HTTP→PostgreSQL 证据，见 [实现验收](verification-integration.md)。
- 四个测试会话均已退出。线上验证记录为本机 `output/releases/calendar-drag-70f85af/cloud-http-verification.json`，部署回执为同目录 `deployment.json`。

## Android 测试包

- 本机文件：`output/releases/calendar-drag-70f85af/pandora-calendar-drag-0.1.2.apk`。
- `versionName=0.1.2`，`versionCode=20261105`，真实 API `http://39.96.84.51/api`，最低 Android 7.0 / API 24。
- 正常 release 构建退出 0，未嵌入验收令牌。`aapt` 确认版本，`apksigner verify` 通过；签名 SHA256 与此前 0.1.1 包一致，可以覆盖安装。
- APK SHA256：`7C23AA1EB0871D0AD944A4C86B20FBAD73FC6E0B7265014F60D2FAE747E83B31`。仍使用项目现有内部测试签名，不是商店发布包。
- 测试流程：安装新版，用有派发／改期资格的账号进入公司→月视图，长按自己派发的可改期任务约 500ms；震动浮起后拖到其他日期，检查整段时长不变，按当前审核政策处理。需要审核时正式任务留在原日期。普通员工及只读成员月历不会因此获得改期权限。

## 备份与回滚

备份目录：`/opt/Grade3_Work-backups/calendar-70f85af-20261104T074514Z`，仅 root 可访问。包含 pg_dump 自定义格式数据库备份（`pg_restore --list` 验证通过）、旧 JAR、原环境／systemd 配置、原服务器 Git 暂存与未暂存差异及发布回执。

上线后回滚应先将 `/etc/collaboration-calendar.env` 的移动开关改为 false 并重启，保留能识别 MOVE 的当前审核消费者和 V27。已经开放过请求，不能直接替换为忽略 MOVE 的旧 JAR；必须先核对待审申请及消费者兼容性。不要自动恢复数据库快照或删除 V27／幂等记录。

## 仍存在的限制

日历专项 59 项、分析、打包和两轮本机 Android 系统链路通过；后端受影响专项为 107/108，全仓仍有失败。模拟器 profile 性能未达到门槛，真实手机／TalkBack、完整人工矩阵及非作者审阅尚未完成。本次部署成功不改变这些结论。
