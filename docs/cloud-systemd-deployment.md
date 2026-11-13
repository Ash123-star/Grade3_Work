# 云端现有 systemd 部署：更新、迁移与回滚

需要丢弃旧数据并初始化6—11月新版场景时，使用 [新空库切换指南](annual-scenario-rebuild.md)，不要在旧库执行下面的legacy场景升级步骤。新版短账号和密码见该文档。

关联 Issue：#44（文档维护，延续 #42 的云端更新）。

## 当前运行版本：必要通知后端（2026-11-12，Issue #86）

按用户要求，提交 `3fec52f65b0f02fec15d092526a302dfae54374d` 的后端已部署并启动，仍由原 `collaboration-server.service` 管理，开机启动已启用，未合并草稿 PR #87。当前实际 JAR 为 `/opt/Grade3_Work-releases/push-3fec52f/server/target/collaboration-server-1.0.0.jar`，SHA-256 为 `abedbb74a9020d249b78a580e1e7a1454c5a2f354374f522dc2986f4e08eb9af`。保留原 Java 21 与 `-Xmx512m`，2026-11-12 13:46:34（上海时间）启动，发布核对时 active/running、NRestarts=0。

本地从该提交的干净 Git archive 重新打包，`mvn.cmd -B -f output/push-deploy-3fec52f/server/pom.xml -DskipTests package` 退出0；上传校验SHA后在独立release目录保存源码及JAR。原 `/opt/Grade3_Work` 工作区、暂存补丁和未跟踪备份保持，四个原环境文件的哈希未变。此次没有重跑完整测试套件，既有实现测试证据及限制见 [后端验证](backend-validation.md#阿里云-android-必要通知issue-86)。

通过原进程环境与容器端口定位实际 `collaboration-data-postgres-1:55432` 的 `workpanel_annual2026` 库，发布前和停写后分别备份，均经 `pg_restore --list` 校验；旧JAR、原unit/drop-in、环境文件及私有补丁保存在 `/root/workpanel-backups/20261112-push-3fec52f`，其中配置仅root可读。新旧JAR中所有既有结构/场景迁移SQL逐字节一致，仅追加 V34；实际Flyway V34成功，三张推送表存在，人员和任务总数不变，没有切库或初始化场景。

本次新增 `/etc/systemd/system/collaboration-server.service.d/zzzzzzz-push-release.conf`，只切换实际JAR路径并设置 `PUSH_ENABLED=false`、`APP_PUSH_ENABLED=false`。EMAS/RAM/华为通道和正式签名尚未完成，不发送真实推送；以后启用须同步处理该drop-in的两个关闭变量，再重新加载systemd并重启，不能只编辑Compose的 `.env`。Android初始化位置还需按官方要求修正，具体未完成项见 [OpenSpec任务](../openspec/changes/android-essential-push/tasks.md)。

公网 `http://39.96.84.51/api` 的16项定向部署检查通过：健康200/UP；既有场景登录、本人资料、任务列表及站内通知可读；通知ETag条件请求304；素材清单和一份OSS图片大小/SHA-256核对成功；未认证偏好401、非法设备400、未配置绑定/启用409，偏好显示configured=false/enabled=false；核对会话已退出且复用令牌401。最终设备及投递记录均为0。证据为本机忽略目录 `output/push-deploy-build.log`、`output/push-deploy-receipt.json`、`output/push-deploy-public-result.json`，不代表手机锁屏送达验收。

回滚时停止服务，将本次 `zzzzzzz-push-release.conf` 移至上述root备份目录，再执行 `systemctl daemon-reload` 和 `systemctl start collaboration-server`，恢复原ExecStart。原release JAR未被覆盖，SHA-256为 `10016818dbc16a1bf0eb801acb6e32fc1835303e81a69d77cec0224958cd94ef`。V34仅增表/索引，回滚保留迁移和业务数据，不向在线库覆盖恢复。

## 2026-11-07 消息缓存修订发布

业务提交 `6f2ec8e606b51799acf7a714efcee64121a2b1c6` 已推送原 PR #77 并部署，未合并main。前后端编译退出0、按要求不运行测试套件；发布后公网健康UP，授权消息请求先返回200及ETag，再发送If-None-Match返回304、正文0字节，已注销核对会话。服务active/running、NRestarts=0，实际数据库和服务器私有补丁保持。新旧JAR迁移SQL逐字节相同，无迁移。必要连通性核对不替代缓存、后台恢复和消息状态的设备验收。

镜像 `workpanel-backend:6f2ec8e` 及local标签已更新，原systemd API实际JAR SHA-256为 `f5ca95f253e58a1a6aa821b87bfe00c454c725facd8d753e2ea0cfea2c08f61a`，与上传及镜像提取结果一致；源码经校验Git bundle同步，干净release worktree保留。发布前及停写后二次实际库备份、旧JAR和配置位于 `/root/workpanel-backups/20261107-notification-6f2ec8e`，备份目录列表可恢复；回滚恢复previous.jar并重启，旧镜像为workpanel-backend:bec8422。记录 `output/yellow-theme/notification-cache-{deployment-receipt,public-result}.json`；本轮未运行测试或更改数据库结构。

必须安装 `output/yellow-theme/workpanel-notification-cache-debug.apk` 才能启用客户端缓存、静默轮询和前台会话保留。未变304只免除正文传输，服务端仍查询并重新校验授权；不将其描述为完整数据库增量同步。

## 2026-11-06 实际更新记录

消息刷新修复已按用户授权部署，代码提交 `bec842266a5be42e4d0587e065c3b4e5a30f569e`，草稿 PR #77；本次未请求合并 main，服务器切换至 `fix/53-notification-refresh`。本机已编译通过的 JAR 经 SSH 上传，Git bundle 校验所需祖先及目标 SHA 后更新源码，并建立同提交干净 release worktree。使用现有运行镜像作为基础，仅替换 JAR，生成 `workpanel-backend:bec8422` 并更新 `workpanel-backend:local`；镜像及线上 JAR SHA-256 均为 `f2d737d2d9fe52fe01c14aef08c423ed8ca62ea983d1421fab9df826cf590d4a`。未启动第二个 API 容器，实际服务仍由 systemd 管理。

发布前备份、停写后二次备份均指向实际 `workpanel_annual2026` 库，`pg_restore --list` 校验成功；旧 JAR、服务配置及服务器私有补丁保存在 `/root/workpanel-backups/20261106-notification-bec8422`。新旧 JAR 中全部数据库迁移 SQL 逐字节相同，无新增迁移、未切换数据库；服务器既有暂存 CI/Dockerfile 修改前后补丁一致，原备份文件保留。重启后 active/running、NRestarts=0，内网及公网 `/api/health` 返回 UP；公网登录后的 `GET /notifications?limit=1&category=任务&unreadOnly=false&search=` 返回200，已核对单条分页、summary及全量unread字段，核对会话已退出。证据在本机忽略的 `output/yellow-theme/notification-{deployment-receipt,public-result}.json`，远端备份目录保留镜像构建日志。

这次仅完成编译及必要的发布连通性核对，按用户要求未运行测试套件；设备刷新、前后台重放、权限和429冷却仍待用户手工验收。移动端需安装 `output/yellow-theme/workpanel-notification-refresh-debug.apk` 才会使用新的分页与刷新逻辑。回滚时恢复该备份中的 `previous.jar` 并重启原服务，镜像可回退 `workpanel-backend:983b7e7`；无需回滚数据库。

PR #74 已合并到 main，业务发布提交 `b3b0a3d4944e8941520e8af358b13661d3221d16`。用户明确豁免本次非作者审阅；本地前后端编译和 GitHub 构建检查通过，按要求没有运行测试套件。云端年度 V2–V6 实际成功，人员和任务核对见[年度场景](annual-scenario-rebuild.md)。

云端 GitHub 直连 fetch 连接重置，因此使用本机 fetch 后生成的增量 Git bundle，经已认证 SSH 上传、校验依赖及 SHA 后快进云端 main。云端原有暂存 CI/Dockerfile 修改与两个备份文件均保留，更新前后补丁逐字节一致。构建在 `/opt/Grade3_Work-releases/<SHA>` 的干净 worktree 完成，没有把服务器私有修改混入镜像。

`workpanel-backend:b3b0a3d` 镜像已生成并标记为 `workpanel-backend:local`。从镜像提取 JAR 后替换原 systemd 服务文件并重启实际 API；没有启动第二个 API 容器或重启数据库容器。服务 active/running、NRestarts=0，本机8080和移动端公网 `/api/health` 均返回 UP。原 JAR、配置、实际库及切换前二次备份位于 `/root/workpanel-backups/20261106-member-enrichment`，不要删除；新镜像存在不代表 API 已部署，仍须核对实际 JAR/进程。

公网 APK 已覆盖安装到 `emulator-5554`，保留应用数据。首次公网登录可用；部署核对另发现 raw 域名在云端超时而 Contents API 可用，后续双入口修复及最终公网结果以对应 PR 的实际发布记录为准。此段是上述提交的运行证据，不代替用户设备界面验收。

## 适用环境与已确认事实

2026-10-29 用户提供的服务器输出确认：

- 项目目录：`/opt/Grade3_Work`，移动端地址：`http://39.96.84.51/api`。
- API 由宿主机 `collaboration-server.service` 管理，运行 `/usr/bin/java -jar /opt/Grade3_Work/server/target/collaboration-server-1.0.0.jar`，监听8080。
- `collaboration-data-postgres-1` 暴露127.0.0.1:55432，`collaboration-data-redis-1` 暴露127.0.0.1:56379。
- 另有 `workpanel-backend-data-1`，暴露55435、56382、57688，是另一套数据服务。原 systemd 的实际连接以服务配置为准，不能只凭容器名称认定业务库。
- 新构建的 `workpanel-backend-api-1` 因宿主机8080已被Java占用而启动失败。镜像构建成功不代表新版服务已启动或场景迁移成功。

本指南保留原 systemd API、原数据库连接与现有反向代理，不新建数据库或切换Compose数据卷。`docker cp` 只从已存在的容器取文件，不创建、不启动容器。此前执行Compose已经创建的容器仍存在；它们不是下面的复制步骤创建的。不要再同时启动Compose的api。

## 1. 更新前确认与备份

在服务器执行：

```bash
cd /opt/Grade3_Work
git status --short
systemctl status collaboration-server --no-pager -l
sudo ss -ltnp 'sport = :8080'
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

工作区如有本地改动先保留，不使用reset覆盖。通过 `systemctl cat collaboration-server` 在服务器本地查看原服务的EnvironmentFile/启动参数，核对DB_URL、DB_USER、Redis和AI配置；不要把含密码的原始配置发到聊天或提交Git。`deploy/backend/.env` 只供Compose读取，编辑它不会自动修改systemd服务。

更新前按原数据库备份流程备份**实际DB_URL所指库**，并保存原服务配置和环境文件。两套PostgreSQL中不能任选一个备份。备份失败先停止更新。本指南不替换原数据库连接配置。

```bash
git switch main
git pull --ff-only origin main
```

## 2. 准备新版JAR（选择一种）

### A. 当前已构建成功且api容器存在

下面不需要启动容器，也不会占用端口。仅在确认该容器含最新main构建产物时使用；之后再拉取新代码，不会自动更新容器里的JAR。

```bash
docker cp workpanel-backend-api-1:/app/app.jar \
  server/target/collaboration-server-1.0.0.jar.new
```

如果容器不存在，不执行 `dc up` 来创建它。改用B；或者明确采用临时容器提取镜像产物的流程，该流程会创建容器，与本节的“复用已有容器”不同。

### B. 后续常规更新：宿主机Java21和Maven构建

构建目录与在线服务JAR分离，避免构建失败或重新打包覆盖当前可启动文件。下面跳过业务测试，仅生成包，不代表验收通过。

```bash
java -version
mvn -version
build_dir=$(mktemp -d /opt/Grade3_Work-build.XXXXXX)
git archive HEAD | tar -x -C "$build_dir"
mvn -B -f "$build_dir/server/pom.xml" -DskipTests package &&
install -m 0644 "$build_dir/server/target/collaboration-server-1.0.0.jar" \
  /opt/Grade3_Work/server/target/collaboration-server-1.0.0.jar.new
```

仅在上面命令成功且`.jar.new`存在时继续。构建目录保存本次产物，完成后可按运维保留策略清理。没有Java21/Maven时先配置构建环境，不能用restart代替构建。

## 3. 本次场景账号简化：一次性配置

只有需要初始化/升级21个虚构场景账号时才开启。真实管理员密码不修改；短账号清单见 [关联场景数据](local-scenario-data.md)。

```bash
sudo install -m 0600 /dev/null /etc/collaboration-scenario.env
sudo tee /etc/collaboration-scenario.env >/dev/null <<'EOF'
SESSION_HOURS=168
SCENARIO_DATA_ENABLED=true
SCENARIO_PASSWORD=123456
EOF

sudo mkdir -p /etc/systemd/system/collaboration-server.service.d
sudo tee /etc/systemd/system/collaboration-server.service.d/zz-scenario.conf >/dev/null <<'EOF'
[Service]
EnvironmentFile=/etc/collaboration-scenario.env
EOF
```

如果上述同名文件已存在，先备份、核对，再修改对应键，不覆盖未知用途的配置。原服务其他环境文件保留；若另有后加载的drop-in或命令行参数覆盖这三个属性，须在服务器本地检查并统一配置。

启动时正式Flyway先更新原DB_URL指定的库；显式启用后，场景Flyway再使用同一DataSource及独立`flyway_scenario_history`执行待执行的V1/V2/V3。不要执行`deploy/postgresql`的独立SQL模型。

V3把原场景登录名改为短名、密码改为本次SCENARIO_PASSWORD并撤销场景旧会话；人员ID、权限、状态和业务关联保留。短名被其他用户占用或种子成员被改动时，V3整批回滚并启动失败；不要删除历史或强行覆盖用户。V3成功后再修改SCENARIO_PASSWORD不会重置已有密码。

## 4. 替换JAR并重启原服务

```bash
test -s server/target/collaboration-server-1.0.0.jar.new &&
cp -a server/target/collaboration-server-1.0.0.jar \
  "server/target/collaboration-server-$(date +%Y%m%d-%H%M%S).jar.bak" &&
sudo systemctl stop collaboration-server &&
mv server/target/collaboration-server-1.0.0.jar.new \
  server/target/collaboration-server-1.0.0.jar &&
sudo systemctl daemon-reload &&
sudo systemctl start collaboration-server
```

命令失败不继续后续步骤，查看错误。本次服务器服务用户为root；若之后改为其他用户，替换前确保JAR及目录对服务用户可读。不要停数据库容器，不运行Compose api来抢占8080，不使用`kill -9`代替服务停止。

## 5. 查看启动结果并关闭初始化

```bash
systemctl status collaboration-server --no-pager -l
journalctl -u collaboration-server -n 150 --no-pager
```

`active`只说明进程状态，应查看应用启动完成及Flyway日志；有需要时在**实际业务库**查询：

```sql
SELECT version, description, success
FROM flyway_scenario_history ORDER BY installed_rank;
```

确认V3成功后，才使用 `boss / 123456`、`admin / 123456`、`bl / 123456`、`zhou / 123456`。不要仅凭镜像构建成功认定迁移完成。关闭场景开关并移除环境文件中的测试密码：

```bash
sudo tee /etc/collaboration-scenario.env >/dev/null <<'EOF'
SESSION_HOURS=168
SCENARIO_DATA_ENABLED=false
EOF
sudo systemctl restart collaboration-server
```

这不会删除账号或数据。以后常规更新：拉取main → 准备新版JAR → 备份替换 → `systemctl restart collaboration-server`。只改环境文件内容后restart即可；修改unit/drop-in后需先daemon-reload。旧APK不会自动改变接口地址，需要另行重新构建安装移动端。

## 6. 启动失败与回滚

- 8080冲突：使用ss定位，只保留原systemd API一个监听者；不要盲目换端口或停止不明服务。
- 连接错误：检查原systemd环境，不复制Compose的`DB_URL=jdbc:postgresql://data:5432/workpanel`给宿主机，也不将55432自行改为55435。
- 场景V3失败：保留日志，处理短名冲突/种子变更后再执行；不修改已发布SQL和Flyway历史。
- AI文件解析：容器JAR提取不会把镜像中的`/usr/local/bin/workpanel-parser-sandbox`和其他运行依赖复制到宿主机。依赖须按原部署维护；本指南不证明AI解析/供应商链路已部署成功，不用关闭安全要求规避缺失依赖。

若新版启动失败，先查看日志，再选择已记录的旧JAR备份恢复。以下备份名需要替换为本次实际备份路径：

```bash
sudo systemctl stop collaboration-server
cp -a /opt/Grade3_Work/server/target/<本次旧JAR备份文件名>.jar.bak \
  /opt/Grade3_Work/server/target/collaboration-server-1.0.0.jar
# 恢复旧版前关闭本次新增的场景开关，保留原环境文件。
sudo tee /etc/collaboration-scenario.env >/dev/null <<'EOF'
SESSION_HOURS=168
SCENARIO_DATA_ENABLED=false
EOF
sudo systemctl start collaboration-server
```

JAR回滚不会撤销已执行的数据库迁移或恢复旧账号密码。需先确认旧版与迁移后数据库兼容；不兼容时需修复前进或按数据库恢复方案在隔离库恢复并核对，不直接往在线库覆盖。

## 执行边界

后续实际部署以文首对应日期、提交和运行产物的记录为准；下方通用步骤不构成执行证据。早期仅文档维护时未执行远程操作的结论不代表当前运行状态。不得将历史构建、健康检查或受控测试外推为手机厂商送达成功。
