# 2026年度场景：新建空库与云端切换

关联：OpenSpec `annual-scenario-dataset`，Issue #46。

## 这次更新了什么

这套数据仅用于用户要求的整库重建，采用**原PostgreSQL实例内新建空库并切换连接**。旧库保留但不再供新版业务使用；不新建Docker数据库、不执行DROP DATABASE、不清表，也不混用deploy/postgresql独立模型。待新库确认可用后，再由运维按保留策略决定旧库是否删除。

正式结构继续使用 `server/src/main/resources/db/migration` V1–V23；场景选项为 `SCENARIO_DATASET=annual-2026`，使用 `db/scenario-annual2026/V1__annual_workplace.sql` 和独立 `flyway_annual2026_history`。旧 `db/scenario` V1/V2/V3未修改。默认legacy保留旧行为；不能只把新选项用于旧库，SQL会明确拒绝已有业务。

## 数据清单和时间规则

- 21个场景账号：17个主公司正常成员、1个隔离公司负责人、2个待确认成员、1个停用成员。另有默认公司的维护账号sysadmin，它不参与场景公司业务。
- 642条个人任务（正常18人共624条，停用成员18条历史任务）。正常成员每月6条，林予安从10月入职后开始；其余正常成员覆盖6—11月，单人至少12条。另有跨人参与/交接，个人数量不靠重复协作记录凑数。
- 工期1—5天为主、少量8天，起点分散，含交叉和跨周/月任务。按角色生成标题与交付要求，前一阶段任务ID写入正文/交接评论，分组体现同一项目阶段；不是数据库约束型依赖图。
- 主公司10条有效置顶公司重点、正常人员个人重点、任务评论与回复、3份可下载附件、直属单级历史审核/创始人免审、管理员待确认申请、近期outbox通知。
- 一人一天一份日志、正文1—3项任务相关工作，taskIds与log_tasks一致；工作日为主，含少量周末记录与缺交。林予安不生成入职前日志，徐景行入职日保留UNKNOWN。停用成员只到8月28日留历史。
- 日志截止到初始化时的上海业务日，最晚2026-11-30；当天为草稿。不伪造未来工作日志、反馈、验收、归档事件。11月在未来时只提前派发计划任务。日期固定2026，不随重启平移。
- 初始化会触发正常记忆来源事件，但脚本暂时禁用外部记忆提取并清空Neo4j连接，避免对大量历史数据自动调用外部模型、或混用旧库图投影；后续启用须单独核对并重建投影，不删除原图数据。

标签直接使用Mock配色：公司重点 `#FFD9A8`、产品体验 `#CFE5FF`、研发质量 `#DCE8F7`、客户交付 `#F5DDC6`、运营计划 `#E7D4FF`。

## 新登录表

统一测试密码：`test12345678`（12字符）。账号满足3–64字符字母/数字/下划线/点/连字符规则。密码仍由SCENARIO_PASSWORD传入并BCrypt存储，不写入SQL或日志。旧scenario.*账号和旧密码不导入新库。

| 新账号 | 姓名 | 身份 |
|---|---|---|
| boss | 顾明远 | 创始人 |
| admin | 许安宁 | 场景管理员 |
| pdir | 沈嘉禾 | 产品总监 |
| rdir | 陆承宇 | 研发总监 |
| ddir | 宋知远 | 交付总监 |
| plead | 方亦宁 | 产品组长 |
| dlead | 程以晴 | 设计组长 |
| rlead | 蒋文博 | 研发组长 |
| tlead | 杜晓棠 | 实施组长 |
| chen | 陈知夏 | 产品经理 |
| lin | 林予安 | 产品助理，10月入职 |
| he01 | 何书瑶 | 交互设计师 |
| xu01 | 徐景行 | 体验设计师 |
| zhou | 周启航 | 后端工程师 |
| zhao | 赵星澜 | 客户端工程师 |
| tang | 唐可欣 | 实施顾问 |
| luo | 罗思齐 | 数据实施 |
| new1 | 叶知秋 | 待管理员确认，无公司业务权限 |
| new2 | 温言 | 待管理员确认，无公司业务权限 |
| off1 | 邵维 | 停用，禁止登录 |
| other | 江亦辰 | 隔离公司负责人，不能访问主公司 |

`sysadmin` 是空库首次引导所需的维护管理员，属于默认公司，首次登录需改密；体验数据请使用boss/admin/zhou，不用sysadmin看场景任务。

## 云端操作（systemd现有部署）

前提：当前服务为 `collaboration-server.service`，运行 `/opt/Grade3_Work/server/target/collaboration-server-1.0.0.jar`，数据库通过本机Docker映射端口访问。**先确保本次代码已合入/拉取，旧JAR不认识新数据集选项。** 本文不代表已在云端执行。

### 1. 拉取并准备新版JAR

```bash
cd /opt/Grade3_Work
git status --short
git switch main
git pull --ff-only origin main
```

若工作区有本地改动先保留，不reset。服务器具备Java21与Maven时，在独立目录打包，不覆盖在线JAR：

```bash
build_dir=$(mktemp -d /opt/Grade3_Work-build.XXXXXX)
git archive HEAD | tar -x -C "$build_dir"
mvn -B -f "$build_dir/server/pom.xml" -DskipTests package &&
install -m 0644 "$build_dir/server/target/collaboration-server-1.0.0.jar" \
  /opt/Grade3_Work/server/target/collaboration-server-1.0.0.jar.new
```

必须构建成功再继续。此命令跳过测试，不是验收通过。若使用Docker镜像提取JAR，参考 [systemd更新指南](cloud-systemd-deployment.md)，必须确认镜像含本次代码；不要启动Compose api抢占8080。

### 2. 一条命令备份原库、建空库并准备连接配置

```bash
sudo python3 scripts/prepare-annual-database.py --new-db workpanel_annual2026
```

脚本读取当前Java进程的DB_URL/SPRING_DATASOURCE_URL，按实际映射端口定位唯一PostgreSQL容器，不猜测55432还是55435；先以0600权限备份原库到/root，再使用原DB_USER创建新空库。数据库用户需有创建库权限；无权限则停止，不改用另一套数据库。

#### 报错“进程没有显式DB_URL/SPRING_DATASOURCE_URL”

此时报错发生在备份、建库、写配置之前，不用删除任何东西。旧服务可能使用JAR默认配置或外部application.yml；脚本不能从环境变量读出URL，所以要求运维明确指定。

先更新本分支脚本，然后查看当前Java到数据库的实际连接端口：

```bash
git pull --ff-only
pid=$(systemctl show collaboration-server --property=MainPID --value)
sudo ss -tnp | grep "pid=$pid,"
```

在服务器本地查看 `systemctl cat collaboration-server` 及其EnvironmentFile、Spring外部配置，核对库名和用户名，不分享包含密码的配置。仓库默认值为 `jdbc:postgresql://127.0.0.1:55432/workpanel` 和用户 `workpanel`；这些只是默认值，不足以证明云端实际使用它。若实际连接端口为55432，且配置确认库名/用户均为workpanel，执行：

```bash
sudo python3 scripts/prepare-annual-database.py \
  --new-db workpanel_annual2026 \
  --source-url jdbc:postgresql://127.0.0.1:55432/workpanel \
  --source-user workpanel
```

如果确认使用55435或其他库名/用户，将参数替换为确认值，不能只因另一套库存在就选择它。显式参数仅指出源库，不关闭备份、目标库已存在拒绝或未知Spring属性覆盖保护。

密码仍优先复用原进程环境/原Spring配置。若原密码只存在外部文件，或psql认证失败，可在服务器本地把该密码存入root持有的0600文件，附加 `--source-password-file /root/workpanel-source-password`；不要在命令行中写密码。脚本会将它写入新的0600环境文件供新服务使用。脚本完成后移除临时密码文件。若命令行/SPRING_APPLICATION_JSON强制指定了数据源，脚本仍拒绝操作，必须先由运维消除高优先级覆盖，避免重启后仍连旧库。

它写入root-only `/etc/collaboration-annual2026.env` 和drop-in `/etc/systemd/system/collaboration-server.service.d/zzzz-annual2026.conf`，保留原用户名、密码、Redis与其他配置。脚本不停止、不重启、不替换JAR，也不删除旧库。存在额外Spring配置、目标库/同名配置已存在或无法确定连接时拒绝执行；先检查输出，不盲目重复。失败后可能留下已备份文件或空库，保留供核对。

配置包含新DB_URL、`SCENARIO_DATA_ENABLED=true`、`SCENARIO_DATASET=annual-2026`、`SCENARIO_PASSWORD=test12345678`、`SESSION_HOURS=168`及默认维护管理员配置。存在别的更晚加载的drop-in或Spring属性覆盖时，须先在服务器本地核对统一；不要发送包含密码的完整配置。

### 3. 备份旧JAR、替换并重启

```bash
cd /opt/Grade3_Work
test -s server/target/collaboration-server-1.0.0.jar.new &&
cp -a server/target/collaboration-server-1.0.0.jar \
  "server/target/collaboration-server-$(date +%Y%m%d-%H%M%S).jar.bak" &&
sudo systemctl stop collaboration-server &&
mv server/target/collaboration-server-1.0.0.jar.new \
  server/target/collaboration-server-1.0.0.jar &&
sudo systemctl daemon-reload &&
sudo systemctl start collaboration-server

journalctl -u collaboration-server -n 150 --no-pager
```

仅systemd应用短暂停机，原数据库容器保持运行。新库会执行正式V1–V23和年度场景V1；查看日志确认两个过程均成功并且应用启动完成。旧客户端token在新库无效，需要重新登录；客户端旧草稿按账号ID隔离，不应作为新场景历史恢复。

### 4. 成功后关闭场景开关

若年度V1报 `42702: column reference "manager" is ambiguous`，正式V1–V23成功不代表场景初始化成功：该错误发生在ApplicationRunner阶段，可能晚于 `Started Application`。先停止systemd的失败重启，再将年度SQL中直属关系查询改为 `SELECT 'annual-'||p.key,'annual-'||p.manager,c FROM annual_people p WHERE p.manager IS NOT NULL;`。此处修复仅适用于年度V1尚未成功且事务已回滚的新库；不得修改其他库已成功应用的迁移或修复校验和来绕过历史。

仅改源SQL不会改变运行JAR，必须重新打包部署。若使用 `git archive HEAD` 构建，须额外将本地修复的SQL复制进构建目录，否则未提交的修复会被遗漏。复用已有新库、环境文件和drop-in，不重复运行建库脚本，不删表或Flyway历史。等待年度 `flyway_annual2026_history` 的V1为success=true、业务数据存在且服务稳定后，才关闭场景开关。仓库已修复SQL，云端执行结果待确认。

```bash
sudo sed -i 's/^SCENARIO_DATA_ENABLED=.*/SCENARIO_DATA_ENABLED=false/; /^SCENARIO_PASSWORD=/d; /^ADMIN_PASSWORD=/d' \
  /etc/collaboration-annual2026.env
sudo systemctl restart collaboration-server
```

保留新DB_URL和annual-2026选项，不删除整个drop-in；否则会切回旧库。账号/任务不删除。不要修改Flyway历史来重新初始化或重置密码。

## 可复现的结果检查（本轮未执行）

### 2026-10-30 云端恢复记录

SSH检查确认云端已修复manager歧义并成功执行年度V1，未再次修改迁移或重建数据库。实际库workpanel_annual2026内有642条任务、1816条日志、10条有效公司重点；正常成员各36条自有任务，10月入职成员12条，停用成员18条历史任务，待确认成员0条。

已备份年度环境文件到云端/root，关闭SCENARIO_DATA_ENABLED并移除一次性密码覆盖，重启systemd服务；检查时MainPID=743853、NRestarts=0、active/running。本机8080健康检查、zhou/boss登录/本人信息/退出均200；移动端公网地址的健康检查、zhou登录/本人信息/退出均200，登录返回有效期168小时。检查会话均已退出，未打印token。未重新编译、运行完整测试或验证移动端界面，其余验收仍待完成。

在新库内可运行：

```sql
SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;
SELECT version, description, success FROM flyway_annual2026_history ORDER BY installed_rank;
SELECT count(*) FROM tasks; -- 642
SELECT count(*) FROM dashboard_items WHERE company_id='annual-cm' AND kind='COMPANY' AND NOT archived; -- 10
SELECT u.account,count(t.id) FROM users u LEFT JOIN tasks t ON t.owner_id=u.id
 WHERE u.profile->>'seedSource'='annual-2026-v1' AND u.status='ACTIVE'
 GROUP BY u.account ORDER BY u.account; -- 每人至少12条
SELECT min(business_date),max(business_date),count(*) FROM daily_logs;
SELECT name,color FROM task_labels WHERE company_id='annual-cm';
```

另需验证新登录、待确认/停用/跨公司拒绝、月历错位、日志关联、附件、事务/幂等、公司重点10条等。本轮沿用用户跳过验收要求，未运行数据库初始化、编译或测试，不能报告上述数量已在云端实际落库。

## 回滚连接

保留旧库不受影响。若要切回旧库，停止服务，将本次新建的drop-in移到systemd加载目录外，再恢复兼容旧库的JAR：

```bash
sudo systemctl stop collaboration-server
sudo mv /etc/systemd/system/collaboration-server.service.d/zzzz-annual2026.conf \
  /root/zzzz-annual2026.conf.disabled
# 如需要，按记录的具体备份路径恢复旧JAR；原环境文件保持原样。
sudo systemctl daemon-reload
sudo systemctl start collaboration-server
```

切回后新库创建的数据不会自动合并回旧库，客户端需要重新登录。切回前核对原场景初始化开关和JAR版本，避免意外运行旧种子增量；两边数据库都不删除。

## 已知不由本次换库解决的问题

用户随后授权将并行的移动端标签改动一并提交：创建/编辑选择器已改为读取 `/api/task-labels`，使用后端名称、颜色和真实ID，覆盖加载/空列表/失效标签反馈；仍未执行编译和联调，需安装新构建的APK后验证。旧APK不会因数据库更换自动修复。管理者的公司任务卡片当前仍查询授权范围，尚未改为仅本人参与任务，该项不由换库解决。
