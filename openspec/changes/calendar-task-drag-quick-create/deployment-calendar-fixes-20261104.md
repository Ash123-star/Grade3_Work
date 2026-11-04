# 月历落点、限流及完整任务行发布记录

2026-11-04（Asia/Shanghai）。用户在收到修复结果、测试包和历史限制后明确要求“合并部署”。按此指令发布，原性能、全仓、真实手机／TalkBack 和非作者审阅缺口继续保留；本记录不代表这些缺口已通过。

## 合并与版本

- [PR #67](https://github.com/Ash123-star/Grade3_Work/pull/67) 已合并至 `main`，合并提交 `81233ef2621da404614e80f788f756d03c543263`，2026-11-04 20:24:42 合并。本地已取得并校验签名合并提交，tree 与测试包对应的修复提交 `5175fdd` 完全相同。
- 此版本包含 C-08 落点日期／重复读取限流和 C-09 完整任务行修复：正式任务不再受三行限制；正式与候选共同决定周高，拥挤周向下展开，后续周下移，取消保留正式任务所需高度。
- APK **0.1.5 / 20261108**，真实 API `http://39.96.84.51/api`，沿用原内部测试签名。SHA256：`bfede00490e3cf4df89ddc03197b1b4a250554986501015230db30443ae79a33`。
- 下载：[pandora-calendar-fix-0.1.5.apk](http://39.96.84.51/downloads/pandora-calendar-fix-0.1.5.apk)。本机留存 `output/releases/calendar-all-rows/pandora-calendar-fix-0.1.5.apk`。

## 服务器操作

服务器 `39.96.84.51`，发布完成 **20:35:00**。

- 从合并提交生成源码归档，上传校验 SHA256 `9a75b922138c9bc33fa3d2d6f01fb30a61632ba6792e3f7718fa3b4490ec96dc`。源码发布至 `/opt/Grade3_Work-releases/calendar-81233ef/source`；原 `/opt/Grade3_Work` 检出中的暂存和未暂存改动摘要均保持不变，没有覆盖原部署配置或备份文件。
- 本轮 `server` tree 与已部署 PR #65 完全相同：`78eea6e7a7537f94875350841ee17c2dca76986b`。运行 JAR 保持 SHA256 `9bc921368af1dcb7ebf3e00264d27bc48bc3e5eebc706dfa6eb37b71db7b3c43`，后端代码仍对应 `70f85af`。无新接口或迁移。
- 已重启 `collaboration-server`，PID `1640832`→`1875865`；健康状态 `UP`，`CALENDAR_MOVE_ENABLED=true`、`SCENARIO_DATA_ENABLED=false` 保持生效。
- Caddy 为版本化 APK 增加精确下载路由，文件位于 `/srv/pandora-releases/pandora-calendar-fix-0.1.5.apk`；其余 IP 请求仍代理现有后端，原域名路由保持。配置验证通过后 reload。
- 部署前后为 **22 个账号、647 条任务、2 条个人事项**；全部任务的 ID／版本／起止时间摘要一致，Flyway 无失败迁移。没有导入演示数据或成功修改线上业务任务。

初次发布前源码校验发现 Git 归档转换了换行，核对规范化内容相同并按实际归档字节校验后继续。随后本机下载探针使用 `127.0.0.1` 的虚拟主机，命中原 HTTPS 跳转；脚本恢复了代理配置。改为正确 Host 后重新验证并完成发布，期间 JAR 未替换，已完成的后端重启未重复执行。

## 验证

- 功能证据沿用 [完整行验收](verification-all-rows.md)：布局受影响回归 15 项、密集与拖动 7 项（有重叠），小屏大字五条＋第六行、十条＋第十一行，以及 Android→HTTP→PostgreSQL 独立审核后六条正式任务完整展示。
- 发布后公网 **33 项 HTTP 检查通过**，包括健康、OpenAPI、四个测试账号登录、月历范围／快照／排期约束、参与人范围、任务看板、个人事项、详情能力、无效零位移 400、过期版本 409、员工越权 403、超长范围拒绝和四个临时会话退出。拒绝请求前后任务版本和排期一致。
- `boss` 当前月有 34 条可改期任务，`admin` 本次前 100 条为 100 条；`zhou`／`zhao` 均为 0。数值是验证快照，权限没有因本次前端发布扩大。
- 公网 APK 全量下载 **HTTP 200、122,975,435 字节、SHA256 与本机一致**；范围下载 **HTTP 206**、ZIP 文件头正确。脚本退出 0，结果见本机 `output/releases/calendar-all-rows/download-verification.json`；发布回执为 `deployment.json`，HTTP 记录为 `cloud-http-verification.json`。
- 发布文档的 `openspec.cmd validate --all --strict`：47/47，退出 0；见 `output/calendar67-deployment-openspec.log`。

## 验收与回滚

安装 0.1.5 后进入公司→月视图：检查第四行及以后任务全部可见；将任务拖入已有五条任务的日期，候选应占第六行且周格增高，后续周下移；核对确认日期、取消恢复和独立审核后的完整显示。已有开始和截止时间的任务保持时长。仅更新服务器不会替换手机上已安装的旧 APK。

代理配置备份：`/opt/Grade3_Work-backups/calendar-client-81233ef-20261104T123457Z/Caddyfile`。需要回滚下载入口时恢复该配置并验证后 reload Caddy；客户端可恢复上一版。后端 JAR、V27 和审核消费者保持兼容，不需要恢复数据库，也不删除改期申请或幂等记录。

本次没有重新跑完整后端套件或 profile 性能矩阵，也未完成真实手机／TalkBack／非作者审阅。原六项验收缺口继续保持未完成，不归档变更。
