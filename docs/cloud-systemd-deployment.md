# 云端现有 systemd 部署：更新、迁移与回滚

关联 Issue：#44（文档维护，延续 #42 的云端更新）。

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

本文记录用户提供的部署事实与操作步骤。未远程执行替换、重启、迁移或回滚，尚未确认原服务实际连接的数据库，也未确认云端V3已成功。按用户要求，本轮文档维护不运行编译或测试。
