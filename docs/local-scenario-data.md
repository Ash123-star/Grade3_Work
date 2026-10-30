# 关联场景数据与本地移动端验收

本文为旧legacy场景。用户于2026-10-30要求整库重建后的年度数据、短账号及新密码，见 [annual-2026新库指南](annual-scenario-rebuild.md)；旧账号表不适用于年度新库。

## 使用范围

用户于2026-10-29确认使用独立启用的 Flyway 数据初始化目录。数据写入**当前后端 DB_URL 指定的数据库**，不会自行创建或切换数据库。企业和人物全部虚构；使用 `scenario-` 对象ID和下表中的短登录账号（V3后），不冒充真实员工资料。

默认启动只运行 `db/migration` 正式结构迁移。显式设置 `SCENARIO_DATA_ENABLED=true` 后，`ScenarioDataBootstrap` 使用同一 DataSource 执行 `db/scenario/V1__related_workplace_data.sql`，但执行记录写入独立的 `flyway_scenario_history`。正式 `flyway_schema_history` 仍为 V23，未来正式 V24 等迁移不受种子版本影响。不要将该 SQL 复制到正式迁移目录。

## 启用方式

1. 配置目标环境原有的 `DB_URL/DB_USER/DB_PASSWORD` 及 Redis 配置。对已有业务库按原部署流程保留备份。
2. 设置 `SCENARIO_DATA_ENABLED=true`，通过环境变量设置测试 `SCENARIO_PASSWORD`（按本次要求使用 `123456`），至少6字符且 UTF-8 不超过72字节。真实环境私密密码不写入Git；本次公开测试密码按用户要求在文档说明。Docker部署也支持这两个变量。
3. 按现有方式启动后端；新库仍须提供初始管理员配置。正式结构迁移成功后，种子迁移在一个事务中追加数据。任意前缀冲突直接报错并回滚，不覆盖已有记录。
4. 确认 `flyway_scenario_history` 中 V1、V2、V3 成功，并通过下列账号登录。全部场景账号使用本次传入的场景密码；仅存BCrypt摘要。
5. 初始化后可以关闭 `SCENARIO_DATA_ENABLED` 并移除 `SCENARIO_PASSWORD`。重启不会移除数据，正式迁移也不依赖该目录。保持开启重启同样不会重复插入、移动历史日期或重置密码。后续场景增量另加该目录的 V4，不能改写已执行的V1。

## 人员关系

| 账号 | 角色/职责 | 直属上级 |
|---|---|---|
| boss | 创始人顾明远 | 无；权限内关键变更免审 |
| admin | 管理员许安宁 | 创始人；成员确认由管理员处理 |
| pd | 产品总监沈嘉禾 | 创始人 |
| rd | 研发总监陆承宇 | 创始人 |
| dd | 交付总监宋知远 | 创始人 |
| pl | 产品组长方亦宁 | 产品总监 |
| dl | 设计组长程以晴 | 产品总监 |
| bl | 研发组长蒋文博 | 研发总监 |
| tl | 实施组长杜晓棠 | 交付总监 |
| chen / lin | 产品经理/新入职产品助理 | 产品组长 |
| he / xu | 交互/体验设计师 | 设计组长 |
| zhou / zhao | 后端/客户端工程师 | 研发组长 |
| tang / luo | 实施顾问/数据实施 | 实施组长 |
| new1 / new2 | 待管理员确认 | 暂未分配 |
| off | 已停用历史成员 | 无 |
| other | 另一公司的员工 | 无；用于跨公司拒绝验证 |

共21名账号、主公司三部门四团队。手机号/性别/年龄不编造，保持空值；邮箱使用保留的 `.example` 域。`lin` 为新入职成员；`xu` 无可靠入职日，用于月历 UNKNOWN 场景。

## 数据场景

- “商户经营看板上线”贯穿指标口径、交互设计、退款聚合、移动端联调、试点培训与客户验收，按各自职责分配。
- 初始30项任务，含多参与人、标签、逾期/未来期限，以及接收、反馈、退回重做、验收、归档和撤回的有序事件。关键创建包含直属单级审核或创始人免审的历史记录。
- 日志按上海业务日、工作日、入职日和任务创建日期关联，跨月且有缺交/新入职/未知入职场景；另有仅作者可读的草稿。
- 任务评论与回复、近期日志评语、6份实际可下载字节材料、待确认成员、待审及驳回改期、公司重点及个人重点。
- 通知只初始化 outbox，由实际投递任务写入通知；审计明确标记历史场景初始化，不声称历史 HTTP 调用。
- 日期在首次迁移时固定；不能反复运行迁移来“刷新”旧数据。长期使用后应按当前业务日期再追加新任务和日志。

## 自动验收工具

`scripts/verify-scenario-runtime.py` 使用 Python 标准库访问真实HTTP服务，不读取数据库或绕过权限。只操作固定场景账号，运行会新增带 `联调验收` 标识的任务与评论、补充当日日志，并确认第一个待确认成员；另一个仍待确认。建议在首次初始化当天运行（日志24小时窗口属于正式规则，过期后工具不应绕过）。

```powershell
python scripts/verify-scenario-runtime.py --credentials <本机凭据JSON路径> --output <结果目录>
```

凭据JSON仅包含 `baseUrl` 和 `password` 即可，置于Git忽略目录。工具输出的 `http-results.json` 不含密码或token，记录路径、角色、状态码和语义断言。若检查失败返回非零退出码，不把缺失配置伪装为成功。

Android本地调试使用 `USE_MOCK=false` 的debug APK，默认访问云端 `http://39.96.84.51/api`；本地模拟器通过 `--dart-define=API_BASE_URL=http://10.0.2.2:8080/api` 覆盖。正式发布包应配置HTTPS。设备验收覆盖五个页签、有关联的业务数据、强制停止后的会话恢复；截图和日志放在 ignored `output` 目录。

## 当前环境边界

用户尚未提供其实际开发数据库连接。本轮执行的目标为本机真实 PostgreSQL 数据库 `workpanel_scenario_20261029_532fbcca`，不是内存数据库或Mock；这**不代表已写入其他未提供连接的业务库**。该种子实现不限制数据库名称，交付后在实际配置的库显式启用即可执行。

## 本次简化账号的云端部署

**现有云端实际由systemd管理。** 请优先使用 [systemd部署、迁移和回滚步骤](cloud-systemd-deployment.md)，配置 `/etc/collaboration-scenario.env`，保留原服务的数据库连接。以下Compose步骤仅适用于原本就以该Compose项目运行API的环境；不能将其直接用于现有systemd服务，否则会产生8080冲突，并可能连接另一套数据库。

V3只处理固定21个场景用户，统一密码由执行V3时的SCENARIO_PASSWORD决定。本次测试密码为 `123456`。V1/V2保持原样；人员ID、权限、状态、任务、日志与组织关系保持不变，V3撤销原会话。短账号已被占用或场景成员被改名时整批回滚，不覆盖其他账号。

在云端拉取main后，在原部署的 `deploy/backend/.env` 设置 `SCENARIO_DATA_ENABLED=true` 和 `SCENARIO_PASSWORD=123456`，然后重新构建并启动：

```sh
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml build api
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml up -d --no-deps --force-recreate api
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml logs --tail=100 api
```

若原部署使用了 `-p`，继续使用相同项目名。确认flyway_scenario_history的V3成功后可关闭场景开关并移除密码，再重建容器配置。后续修改环境变量不会再次重置密码。尚未远程部署，本地代码修改不代表云端账号已更新。
