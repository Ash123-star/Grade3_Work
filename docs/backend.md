# 企业协作后端

后端实现位于 `server/`，Java 21 / Spring Boot 3.4 / PostgreSQL 16 / Redis 7。业务通过同一套 `/api` REST 接口供 Android 与 Web 使用。移动端当前仍是演示数据仓库，接入此服务和独立 Web 工作台属于后续客户端工作。

## 启动

需要 Docker Desktop（Linux 容器）和 Compose v2。复制 `deploy/backend/.env.example` 为 `.env`，填写 `DB_PASSWORD`、`REDIS_PASSWORD`、`ADMIN_ACCOUNT`、`ADMIN_PASSWORD`、`ADMIN_PHONE`。密码无默认值；管理员密码至少 12 个字符且 UTF-8 编码不超过 72 字节。手机号需满足大陆手机格式。

Redis 密码使用字母、数字、下划线或连字符，建议随机生成至少 32 字符。后端部署目录包含自身的 Redis 配置与启动脚本，可独立于此前的数据部署包使用。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start-backend.ps1
```

首次运行缺少 `.env` 时，脚本创建空配置模板并提示填写。Flyway 自动执行三个追加式迁移，预置产品部、市场部、技术部。初始化管理员由环境变量创建并记录审计；重复启动不覆盖现有账号或密码。数据库已初始化后，更改环境变量不会更改既有数据库密码。

| 服务 | 本机地址 | 说明 |
| --- | --- | --- |
| API | http://127.0.0.1:8080/api | `SERVER_PORT` 可配置 |
| Swagger UI | http://127.0.0.1:8080/api/docs | 可查看请求模式并填写 Bearer 会话 |
| OpenAPI | http://127.0.0.1:8080/api/openapi | 双端共用机器契约 |
| PostgreSQL | 127.0.0.1:55435 | 数据库及用户 `workpanel` |
| Redis | 127.0.0.1:56382 | 请求限流、AI 预算 |

部署使用独立 Compose 项目 `workpanel-backend` 和独立持久卷。已有 `deploy/compose.yaml` 数据基础包使用另一套 UUID 表结构；此后端的 Flyway 表不能直接应用到该已迁移数据库。现有数据基础环境保持独立，此服务用新的空库初始化。

```powershell
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml ps
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml logs --tail 50 api
docker compose --env-file deploy/backend/.env -f deploy/backend/compose.yaml down
```

停止不带 `-v`，保留数据。正式 HTTPS 部署时设置 `API_DOMAIN` 为已指向服务器的域名、设置真实 `CORS_ORIGINS`，开放 80/443 后运行 `scripts/start-backend.ps1 -Https`。Caddy 自动申请证书并对 SSE 及时刷新；API、数据库、Redis 的宿主端口绑定回环地址。生产域名与证书签发需在实际部署环境验收。

如需本机 Java 调试，配置 `DB_URL`、`DB_USER`、`DB_PASSWORD`、`REDIS_HOST`、`REDIS_PORT`、`REDIS_PASSWORD` 及首次管理员变量，运行 `mvn.cmd -f server/pom.xml spring-boot:run`。数据库必须为空库或本后端 Flyway 管理的库。

## 管理员与独立复核引导

1. `POST /api/auth/login` 后首次只能读取本人、改密或登出；`POST /api/auth/password` 撤销全部旧会话，重新登录。
2. 第二名用户通过注册成为待确认员工。管理员审批其 `MEMBERSHIP` 请求，确认部门。
3. 该员工提交 `POST /api/organization/reviewer-application`，管理员独立审批后取得公司复核职责。员工角色和本人业务范围保持不变，仅能查看明确分配给自己的审核候选。
4. 管理员的组织、角色、公司展示等修改由该独立复核人审核。无独立公司复核人时保持待审；补齐人员后申请人可 `POST /api/reviews/{id}/reroute`。已审核过的链不能直接重路由。

管理角色：`ADMIN` 管理员、`FOUNDER` 创始人、`DIRECTOR` 部门老总、`LEADER` 团队长、`EMPLOYEE` 员工。`dispatchEnabled` 可撤销管理者派发资格；给员工开启该开关不会赋予派发角色。`companyReviewer` 只授予独立审核职责。调岗后的下一次请求重新计算范围，停用撤销会话。组织、团队部门组合与汇报循环由服务端验证，复合外键再次限制公司关联。

## 接口与并发

详细请求示例见 `docs/backend-api.md`；机器契约由运行服务生成。分页 `{items,total,nextCursor}`，`cursor` 是从 0 开始的偏移量，`limit` 为 1–100。记录字段当前保留数据库的下划线命名，命令使用驼峰字段；前端须在 data 层映射，不能直接套用演示 command DTO。

每个 HTTP 响应含 `X-Trace-Id`，错误体 `{code,message,traceId}`。未授权对象通常返回 404，明确的人员筛选越权返回 403。请求拒绝未知字段；新增记录 `version:0`，后续修改提交当前版本，冲突返回 409。审核申请含生效前值、候选值和审核链，最终通过前旧版生效。驳回原因必填，修订重提使用原业务修订入口，已提交日报的原内容和历史保留。

任务列表包含表单信息而无完成情况/状态列；流转只能从详情 `events` 读取。提交已发布任务修订后按公司任务策略逐层审核；策略变更也需独立审核，公司复核不可关闭。关键修订生效重置为待接收，旧流转保留在时间线，统计仅采用最近修订后的有效验收。一个主负责人，多人独立负责可创建独立任务；可选协作人和受控附件支持。

日志按本人 + 上海业务日期唯一。上级只读取已提交内容，草稿和私人备注不进入穿透、导出或 AI 输入。日/周/月查询统一计算本地边界再转 UTC，周一起算。报表显示分子、分母、区间和更新时间；日报分母当前按在职范围人数乘截至今天的自然日，未接入节假日与入职日历。CSV 最多 10000 条并处理公式注入字符。

附件以受控字节保存在 PostgreSQL，最大 10MB，无公开静态 URL。下载重新检查当前公司、任务参与范围或授权面板头像。已移出任务的旧附件不会因保留关联而继续对任务参与者开放。

事务 outbox 与业务一起提交，每两秒投递通知并按事件键去重。每分钟产生 24 小时内截止提醒。消息流 `GET /api/notifications/stream` 使用 `Last-Event-ID` 递增序号重放，55 秒后重连；每次发送重新鉴权，撤销会话会结束流。首期为站内消息。

## DeepSeek

仅服务端持有 `DEEPSEEK_API_KEY`；配置 `DEEPSEEK_BASE_URL`（默认 https://api.deepseek.com）和 `DEEPSEEK_MODEL`（默认 deepseek-chat，部署时按 [官方文档](https://api-docs.deepseek.com/) 选择可用模型）。未配置密钥返回 503 `AI_NOT_CONFIGURED`，日志和任务照常工作。

`POST /api/ai/jobs` 保存范围内必要业务文本及来源；后台异步读取 DeepSeek SSE。支持查询、流式观察、取消和新 job 重试；尚无输出时最多重试一次。输入剔除用户凭据、手机号及私人备注，对业务文本中常见密码/手机号标记做隐藏；提示语作为数据处理。所有结果结构、来源和候选负责人再次校验，job 和地图只归生成者本人所有。调岗导致来源失权后，旧 job 也拒绝读取，地图过滤失权节点。

默认每分钟 5 个 AI 请求，每日每人 50000 tokens（UTC 日界），单次输出最多 2000 tokens。输入限制 60000 字符。调用前按文本长度与输出上限保守预留预算；收到供应商用量后结算。失败/取消且未收到用量时保留预留消耗；数据库记录与 Redis 限额共同防止清空缓存绕过预算。用量统计显示该保守口径。

成功输出均带 `draft:true`、来源和生成时间。用户可编辑摘要、节点、行动；修改检查版本并保留生成时间，增加编辑时间，重建该 job 节点时清理旧连接。用户确认完整任务后 `confirm-task` 才进入普通派发鉴权及幂等事务。模型自身不调用业务写接口。

当前 worker 为单实例。服务重启把中断的 `RUNNING` job 标为可重试失败；不要横向启动多个 API 副本，直到增加 worker 租约和跨实例取消路由。

## 验证与备份

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
openspec.cmd validate --all --strict
powershell -ExecutionPolicy Bypass -File scripts/backup-backend.ps1
```

测试脚本创建随机名称、随机本机端口和随机密码的独立 PostgreSQL/Redis 容器，执行 Maven verify 后仅清理自己创建的容器；外部 DeepSeek 由本机 HTTP 模拟服务覆盖，不消耗真实供应商额度。报告在 `server/target/surefire-reports`。实际验证结果见 `docs/backend-validation.md`。

本机 Java 进程因 Windows 提交内存不足无法启动时，可以加 `-DockerMaven`，在限制为 1GB/2 核的 Java 21 容器内运行同一套测试，数据库连接使用 `host.docker.internal`。该方式复用用户 Maven 缓存，不需额外安装 Java；普通方式需要本机 Java 21 和 Maven 3.9。Docker 构建会在受限内存的 Maven 阶段打包，再生成非 root JRE 运行镜像。

备份为 PostgreSQL 自定义格式，包含账号、业务、审计、通知、AI 和附件，默认位于被 Git 忽略的 `deploy/backend/backups/`。Redis 只存临时限流及预算，持久业务用量保存在 PostgreSQL。备份文件应按业务数据管理访问权限，并单独保存 `.env`。

恢复到全新隔离数据库，先停止 API 写入，再 `docker cp` 备份入数据库容器，通过 `pg_restore -U workpanel -d <新库> --no-owner --no-privileges <容器内路径>` 恢复；核对 Flyway 历史和行数后将 API 指向新库。不在现有业务库上直接覆盖恢复。应用回滚保持数据库迁移向前，新增结构通过下一个 Flyway 版本调整。
