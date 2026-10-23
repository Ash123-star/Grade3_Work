# AI办事部署与回滚

2026-10-22 主线协调后的当前镜像为 `workpanel-backend:ai-work-reconciled`（37d43f66bf57）。后端已连接最终恢复副本 `workpanel_ai_upgrade_9ac0fd9b53f5`，正常 Flyway V18 校验/启动、健康 UP、真实登录/事项/任务/日志读取及 Web 管理员工作台通过；原库 `workpanel` 历史保持不变。68 个业务表和数据库序列在转换前后比对一致，独立删除标记已重放，自动写入仍 false。备份、前后摘要与切换回执在忽略目录 `output/ai-work-reconciliation/final-20261022-172125/`、`promotion-result.json`；旧 API `workpanel-ai-api-before-lineage-20261022-172125` 停止保留。下文旧镜像、旧迁移号与混合工作区阻塞均为历史；当前规则与剩余验收限制不变。

上一批镜像 `workpanel-backend:ai-work-delivery-final` 包含 delivery-rules-2 及只读检查空动作修复，此次全部保留。60 场景的真实 OCR/DeepSeek 结果见 OpenSpec 批次验收，仍不满足正式自动写入开放条件，禁止仅凭任务 9.7 已勾选就开启写入。

2026-10-22 本批运行状态优先于下文历史记录：已先执行 pg_dump 并导出删除标记，再更新本地 API 至 `workpanel-backend:ai-work-final`，Flyway 当前 V18，健康 UP，正式自动写入仍 false；数据库、会话和数据卷保留。备份位于忽略目录 `output/ai-work-runtime/backups/20261022-batch/`，旧 API 容器停止保留为 `workpanel-ai-api-before-batch`。新版 APK 已安装到 App_Run_API37。OCR 仍仅内网、只读、2GB/2CPU，已补齐 `on-failure` 重启设置，避免推理硬超时退出后持续不可用。

2026-10-22本地恢复：Docker已恢复，新版`workpanel-ai-api-main`监听127.0.0.1:8080，实际认证/能力查询通过；API通过`workpanel-ai-service`内的`pandora-stage-data-1`使用5432/6379/7687，不再依赖恢复后无法连接的宿主Redis转发端口。数据容器/卷及会话保留，V16无需新迁移。运行镜像包含受验`workpanel-parser-sandbox`并强制`AI_PARSER_SANDBOX_REQUIRED=true`；OCR切到完整锁镜像`workpanel-ocr:locked-acceptance`，只读/2GB/2CPU/禁外网配置保留。执行开关false；仍未达到代表样本/设备/人测发布条件。

本批模板预填与文档提取共用解析沙箱及30秒进程限制。DOCX 支持跨文字段的姓名/部门/日期/事由占位符及表格/页眉页脚，XLSX 只替换字符串单元格；未知占位符、公式和审核字段保留人工核对。产物即时受权下载，不生成公共地址，不改变原模板。子进程终止后等待退出再清理临时目录。未增加数据库迁移。

2026-10-21：本地开发实现，自动写入保持关闭，未达到正式发布条件。证据见 `openspec/changes/ai-work-assistant/validation.md`。

## 当前迁移序列与恢复副本升级

统一序列保留主分支已发布的 V1–V15，新增 V16 `ai_work_assistant`、V17 `durable_delivery_checks`、V18 `ai_authorization_policy`。新库和主分支 V15 库走正常 Flyway，不运行协调工具，不设置常驻 outOfOrder。本文下面关于旧 AI V14/V15/V16、日志 V17/V18 及不能升级 main 的文字是协调前的历史记录；当前决定见 [协调与验收](../openspec/changes/ai-work-assistant/reconciliation-2026-10-22.md)。

仅已经执行旧 AI V14–V16（可含旧日志 V17/V18）的开发库需要恢复副本转换。完成当前后端验收并生成 JAR 后，将数据库密码配置到当前进程 `DB_PASSWORD`，执行：

```powershell
python scripts/upgrade-ai-work-clone.py --source-container <数据容器> --source-database <源数据库> --database-user workpanel
```

脚本只读取源库：导出自定义格式备份及 SHA256、恢复到随机命名 `workpanel_ai_upgrade_<12 hex>`，然后调用独立 Java 工具。转换检查完整 V1–V16/17/18 的名称、版本、描述、类型、成功标记和已知校验和；只移动版本及脚本名，保留安装顺序/时间/人及原校验和，再补齐缺失日志迁移并执行普通 Flyway 校验。非恢复副本、其他连接、失败/缺失/未知/重复历史或关键表缺失一律拒绝。不会自动在应用启动时运行，也不执行 repair。

忽略目录 `output/ai-work-migration-upgrade/<id>/result.json` 保存前后历史和所有业务表的行数/内容摘要（不输出原文）。只有 `passed=true` 且业务摘要一致才可切换。先在线演练；正式切换时停止全部 API/worker，再导出独立删除标记、重新运行脚本制作最终副本、校验结果、按现有恢复流程重放删除标记，更新 API 的 DB_URL 指向新副本。保留 Redis/Neo4j 和附件卷配置；数据库中的旧 ID、审核、回执、会话关联不变。启动后核对健康、登录、事项和任务读取，执行开关继续 false。不要将演练时过期的副本接入运行服务。

失败副本和备份保留供检查，不能投入使用；源库保持不变。切换失败时停止新 API，恢复旧镜像及源库连接；切换后如已经产生新的业务写入，不得直接回切丢弃新记录，须先停写并核对增量。禁止重置卷或删除历史业务。

## 迁移与开关（协调前历史记录）

V14新增私人事项/步骤/授权/回执、正式资料/版本、任务清单/报告；V15新增异步检查队列。不修改V1–V13，不删除旧任务/AI作业。附件保留task_id兼容。PROCEDURE是独立复核kind，回退旧后端前停止新申请并处理存量；禁止降级后继续写新表。

```dotenv
AI_WORKBENCH_ENABLED=true
AI_WORK_EXECUTION_ENABLED=false
AI_OCR_ENABLED=false
AI_OCR_URL=http://ocr:8000
```

DeepSeek复用服务端配置及原预算/限流。客户端、OCR和文档子进程不持有模型密钥。执行器两个槽，交付检查一个槽，PG租约/fence、最多3次尝试；外部处理在业务事务外。入口、写入、OCR独立开关，OCR失败可以补文字，手工任务/日志仍可用。

## 本地OCR

来源为PaddlePaddle官方GitHub及Apache官网/GitHub，不使用百炼。PaddleOCR3.0.3、PaddlePaddle3.0.0、PDFBox3.0.6、POI5.4.1均Apache-2.0；Pillow11.3.0为HPND，FastAPI为MIT，Uvicorn为BSD-3-Clause。官方模型在构建期预置，运行期不下载。OCR Dockerfile直接从 `requirements.lock` 安装完整固定版本，并运行 `pip check`；`requirements.txt` 和 `compatibility.txt` 保留为依赖来源/兼容约束记录。

来源登记：[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)、[PaddlePaddle](https://github.com/PaddlePaddle/Paddle)、[PDFBox](https://pdfbox.apache.org/)、[POI](https://poi.apache.org/)。锁镜像构建实际预置`PP-OCRv5_server_det`与`PP-OCRv5_server_rec`，模型随镜像分发，生产使用已验收镜像摘要，重新构建后须重跑识别验收，不能仅因模型名相同就假定权重相同。

有compose插件时，从根目录运行：

```powershell
docker compose -f deploy/ocr/compose.yml up -d --build
```

本机无compose插件，已用等效方式构建和运行：

```powershell
docker build -t workpanel-ocr:3.0.3 deploy/ocr
docker network create --internal workpanel-ai-parser
docker run -d --name workpanel-ai-ocr --restart on-failure --network workpanel-ai-parser --memory 2g --cpus 2 --pids-limit 128 --read-only --tmpfs /tmp:size=128m,mode=1777 --cap-drop ALL --security-opt no-new-privileges:true workpanel-ocr:3.0.3
```

镜像 `a8b786cbb172` 已通过ready和真实中文识别。以UID10001运行，只读根目录、128MB临时盘、2CPU/2GB、无特权、内网禁止外连。后端容器加入同一网络，用 `http://workpanel-ai-ocr:8000`；后端通过其正常出站网络访问模型，不给OCR连接外网。

当前Docker环境internal网络端口不能供Windows宿主访问，`127.0.0.1:58001`不是已验证生产地址。供应商验收脚本临时转发localhost到容器内部HTTP，退出即关闭，只用于隔离验收。配置模板默认OCR关闭。

本机已将后端迁为 `workpanel-ai-api-main` 容器，监听127.0.0.1:8080，同时接入普通服务网络及 `workpanel-ai-parser`，使用上述容器地址访问OCR；OCR只接内网。该本地运行配置OCR开启、自动写入关闭，数据库和现有会话保留。镜像标签 `workpanel-backend:ai-work-assistant`，本机数据库迁移前备份保存在忽略目录 `output/ai-work-runtime/backups/`。此为本地验证部署，正式环境仍需接入运维配置。

文档使用独立256MB/128MB metaspace/1CPU子JVM，30秒硬终止并清理临时目录。PDF≤50页、图片≤20MP、表格≤50000格、ZIP展开≤100MB。扫描PDF全文件90秒前后检查，单次OCR≤30秒，不把超时保存为成功。后端镜像会编译 `workpanel-parser-sandbox`，用 seccomp 拒绝解析子进程的 socket 系统调用，并限制 CPU 时间、地址空间、单文件大小、文件描述符和 core dump；镜像构建会运行探针确认网络 socket 被拒绝且资源限额生效。Compose 强制 `AI_PARSER_SANDBOX_REQUIRED=true`，缺少可执行沙箱时解析失败关闭。部署环境仍须以实际构建日志和运行镜像核验该探针，不应仅凭源码视为生产验收通过。

文件契约现统一由AiFilePolicy提供，两端读取能力限值；AI上传携带purpose=AI_WORK，普通附件继续兼容。隔离解析拒绝宏、嵌入对象、外部关系和PDF主动内容，并由操作系统级 seccomp 沙箱隔离文档子进程。解析器版本提升为v3，旧缓存不复用，旧检查报告返回失效并要求复检；本批不新增数据库迁移。自动写入开关关闭仍可运行纯检查，不开放正式反馈。

## 保留、故障与回滚

事项实时恢复不新增迁移。反向代理须保留text/event-stream、Authorization和Last-Event-ID，不缓冲SSE；55秒连接正常关闭后客户端自动重连。来源/权限视图改变使用refresh要求重新GET，失权access-lost后停流。部署新版服务端时两端可通过GET与持久事件恢复；正式业务写入开关仍默认关闭。

Flutter恢复补丁要求服务端返回完整v1能力/分页/事项结构（含contractVersion、nextCursor、身份/版本及消息/步骤/回执集合），损坏或不兼容响应会停止当前提交并提示刷新。能力接口刷新失败时保留已输入内容和材料、暂停发送，恢复后可继续；账号切换清理私人输入。取消/续办不删除既有正式结果。本补丁只升级APK，使用当前V16服务，无需重启数据库或修改已发布迁移；回滚客户端不撤销正式任务/交付。

V16新增companies.ai_authorization_revision、个人授权policy_revision及检索索引，保留V14/V15不变。AI授权公司限制复用review_policy并经POLICY独立复核；公司生效边界通过共享/排他行锁与在途动作串行。旧授权失效后需本人重新开启，回退应用不得把已失效授权恢复。升级前备份，执行开关仍保持false。

解析缓存7天，完成事项原始私人材料30天，90天无活动先停后隐藏，每小时清理。主动删除立即停止私有读取/新动作，物理清理异步进行。未用于正式交付的私人检查作业/报告90天清理，正式交付引用的报告保留。正式任务/交付/制度附件及头像按用途保留，不级联删除正式业务。AI动作/授权审计365天后清理详情，保留操作者、类型、对象、时间和幂等回执；其他业务审计不受影响。个人授权创建与撤回同事务记录审计，同键重试不重复写入。

先关闭写入，核对租约、回执、任务和outbox，再按需关闭入口/OCR、切回旧UI。数据库只向前兼容，不DROP表、不删除正式业务。恢复备份时停止所有连接该库的API/worker，保持执行关闭，恢复删除标记/回执并核对后再开放。

`scripts/ai-work-deletion-markers.py` 通过数据容器本地psql导出和重放删除标记，不读取或输出密码。标记只有公司ID/事项ID/删除时间，必须独立于数据库备份保管，配置备份流程及定时任务持续导出，恢复前再导出一次；同一个文件合并已有标记，不能因恢复旧库覆盖新标记。恢复重放拒绝运行中的API容器，在单事务中重新隐藏事项、提高fence、停止待办、清除私有消息/计划/缓存/材料，保留正式文件与回执。部署者仍须停掉其他副本；本地容器检查不能证明集群已全部停止。最新标记文件丢失或未覆盖删除时间时，保持写入关闭并先补齐标记。

```powershell
python scripts/ai-work-deletion-markers.py export --container workpanel-backend-data-1 --database workpanel --file D:/private-backups/ai-work-deletions.json
# 将最新标记独立保存；恢复数据库时API应已停止。恢复后、启动API前执行：
python scripts/ai-work-deletion-markers.py apply --container workpanel-backend-data-1 --database workpanel --api-container workpanel-backend-api-1 --file D:/private-backups/ai-work-deletions.json
```

## 发布门槛

2026-10-22 新验收批次和主分支 #23 接入决策见 [批次说明](../openspec/changes/ai-work-assistant/acceptance-batch-2026-10-22.md)。本地已执行 AI V14/V15/V16 保留，日志能力通过 V17/V18 前向接入；已执行 main 日志 V14/V15 的数据库暂不能直接升级到本工作区，不能用 repair 掩盖迁移历史冲突。

60份合成截图已调用真实本地OCR与DeepSeek：58份形成待确认/追问，2份失败，候选负责人/期限误匹配为0；不能宣布全样本通过。锁镜像中文冒烟11.937秒、全文匹配且内网外连拒绝，尚不能证明OCR P95≤5秒。本地pg_dump/restore删除标记重放已演练，生产部署仍须配置独立标记保存和全副本停机。多页/历史文件/同名等代表样本、服务器20并发完整矩阵、Android真机profile/TalkBack及5位首次使用者仍待验收。正式自动写入保持false。

2026-10-22开发环境限制：C盘耗尽曾导致Docker数据文件系统只读；释放本次编译缓存后Docker仍因IPC socket错误无法启动，当前API/OCR容器没有重新运行。最后代码以隔离本机PG18/Redis5和WSL Linux解析沙箱补验，不能据此声称Compose部署成功。先修复Docker Desktop启动环境，再使用已记录的镜像/源文件重建并核验健康；不要删除数据卷或重置Docker来替代恢复。
