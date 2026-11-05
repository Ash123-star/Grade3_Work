# AI办事部署与回滚

长期运行、安全、迁移与恢复方式维护在本文，功能和未完成验收见 [tasks](../openspec/changes/ai-work-assistant/tasks.md)，正式契约见 [API](ai-work-assistant-api.md)。历史局部容器健康/镜像标签不代表当前机器状态，部署前须核对实际服务与数据库；自动写入未满足发布门槛时保持关闭。

## 当前迁移序列与恢复副本升级

统一序列保留主分支已发布的 V1–V15，新增 V16 `ai_work_assistant`、V17 `durable_delivery_checks`、V18 `ai_authorization_policy`。新库和主分支 V15 库走正常 Flyway，不运行协调工具，不设置常驻 outOfOrder。原AI旧编号冲突已通过严格恢复副本转换协调；禁止把旧“main库不能升级”的结论当作当前限制。后续迁移仍按当前server Flyway链向前执行。

仅已经执行旧 AI V14–V16（可含旧日志 V17/V18）的开发库需要恢复副本转换。完成当前后端验收并生成 JAR 后，将数据库密码配置到当前进程 `DB_PASSWORD`，执行：

```powershell
python scripts/upgrade-ai-work-clone.py --source-container <数据容器> --source-database <源数据库> --database-user workpanel
```

脚本只读取源库：导出自定义格式备份及 SHA256、恢复到随机命名 `workpanel_ai_upgrade_<12 hex>`，然后调用独立 Java 工具。转换检查完整 V1–V16/17/18 的名称、版本、描述、类型、成功标记和已知校验和；只移动版本及脚本名，保留安装顺序/时间/人及原校验和，再补齐缺失日志迁移并执行普通 Flyway 校验。非恢复副本、其他连接、失败/缺失/未知/重复历史或关键表缺失一律拒绝。不会自动在应用启动时运行，也不执行 repair。

忽略目录 `output/ai-work-migration-upgrade/<id>/result.json` 保存前后历史和所有业务表的行数/内容摘要（不输出原文）。只有 `passed=true` 且业务摘要一致才可切换。先在线演练；正式切换时停止全部 API/worker，再导出独立删除标记、重新运行脚本制作最终副本、校验结果、按现有恢复流程重放删除标记，更新 API 的 DB_URL 指向新副本。保留 Redis/Neo4j 和附件卷配置；数据库中的旧 ID、审核、回执、会话关联不变。启动后核对健康、登录、事项和任务读取，执行开关继续 false。不要将演练时过期的副本接入运行服务。

失败副本和备份保留供检查，不能投入使用；源库保持不变。切换失败时停止新 API，恢复旧镜像及源库连接；切换后如已经产生新的业务写入，不得直接回切丢弃新记录，须先停写并核对增量。禁止重置卷或删除历史业务。

## 能力开关

```dotenv
AI_WORKBENCH_ENABLED=true
AI_WORK_EXECUTION_ENABLED=false
AI_OCR_ENABLED=false
AI_OCR_URL=http://ocr:8000
```

DeepSeek仅由服务端配置；客户端、OCR和文档子进程不持有模型密钥。执行器两槽、交付检查一槽，PG租约/fence、最多3次尝试；外部处理在业务事务外。入口、写入、OCR独立开关，OCR失败可补文字，不阻塞手工任务/日志。模板预填使用同一沙箱，未知占位符/公式/审核字段留待人工核对，产物受权下载、不改原模板或生成公共链接。

## 本地OCR

来源为PaddlePaddle官方GitHub及Apache官网/GitHub，不使用百炼。PaddleOCR3.0.3、PaddlePaddle3.0.0、PDFBox3.0.6、POI5.4.1均Apache-2.0；Pillow11.3.0为HPND，FastAPI为MIT，Uvicorn为BSD-3-Clause。官方模型在构建期预置，运行期不下载。OCR Dockerfile直接从 `requirements.lock` 安装完整固定版本，并运行 `pip check`；`requirements.txt` 和 `compatibility.txt` 保留为依赖来源/兼容约束记录。

来源登记：[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)、[PaddlePaddle](https://github.com/PaddlePaddle/Paddle)、[PDFBox](https://pdfbox.apache.org/)、[POI](https://poi.apache.org/)。锁镜像构建实际预置`PP-OCRv5_server_det`与`PP-OCRv5_server_rec`，模型随镜像分发，生产使用已验收镜像摘要，重新构建后须重跑识别验收，不能仅因模型名相同就假定权重相同。

有compose插件时，从根目录运行：

```powershell
docker compose -f deploy/ocr/compose.yml up -d --build
```

无Compose插件环境可采用等效隔离方式（镜像标签替换为实际验收版本）：

```powershell
docker build -t workpanel-ocr:3.0.3 deploy/ocr
docker network create --internal workpanel-ai-parser
docker run -d --name workpanel-ai-ocr --restart on-failure --network workpanel-ai-parser --memory 2g --cpus 2 --pids-limit 128 --read-only --tmpfs /tmp:size=128m,mode=1777 --cap-drop ALL --security-opt no-new-privileges:true workpanel-ocr:3.0.3
```

历史镜像曾通过ready和中文识别；部署时重新核对实际摘要和ready。以UID10001运行，只读根目录、128MB临时盘、2CPU/2GB、无特权、内网禁止外连。后端容器加入同一网络，用 `http://workpanel-ai-ocr:8000`；后端通过其正常出站网络访问模型，不给OCR连接外网。

internal网络不应对宿主/外网公开OCR；验收转发仅用于隔离测试，配置模板默认OCR关闭。

后端同时接普通出站网络与OCR内网，OCR仅接内网；历史本地验证容器名不作为固定配置。正式部署核对镜像、备份与能力开关。

文档使用独立256MB/128MB metaspace/1CPU子JVM，30秒硬终止并清理临时目录。PDF≤50页、图片≤20MP、表格≤50000格、ZIP展开≤100MB。扫描PDF全文件90秒前后检查，单次OCR≤30秒，不把超时保存为成功。后端镜像会编译 `workpanel-parser-sandbox`，用 seccomp 拒绝解析子进程的 socket 系统调用，并限制 CPU 时间、地址空间、单文件大小、文件描述符和 core dump；镜像构建会运行探针确认网络 socket 被拒绝且资源限额生效。Compose 强制 `AI_PARSER_SANDBOX_REQUIRED=true`，缺少可执行沙箱时解析失败关闭。部署环境仍须以实际构建日志和运行镜像核验该探针，不应仅凭源码视为生产验收通过。

文件契约现统一由AiFilePolicy提供，两端读取能力限值；AI上传携带purpose=AI_WORK，普通附件继续兼容。隔离解析拒绝宏、嵌入对象、外部关系和PDF主动内容，并由操作系统级 seccomp 沙箱隔离文档子进程。解析器版本提升为v3，旧缓存不复用，旧检查报告返回失效并要求复检；本批不新增数据库迁移。自动写入开关关闭仍可运行纯检查，不开放正式反馈。

## 保留、故障与回滚

事项实时恢复不新增迁移。反向代理须保留text/event-stream、Authorization和Last-Event-ID，不缓冲SSE；55秒连接正常关闭后客户端自动重连。来源/权限视图改变使用refresh要求重新GET，失权access-lost后停流。部署新版服务端时两端可通过GET与持久事件恢复；正式业务写入开关仍默认关闭。

Flutter恢复补丁要求服务端返回完整v1能力/分页/事项结构（含contractVersion、nextCursor、身份/版本及消息/步骤/回执集合），损坏或不兼容响应会停止当前提交并提示刷新。能力接口刷新失败时保留已输入内容和材料、暂停发送，恢复后可继续；账号切换清理私人输入。取消/续办不删除既有正式结果。客户端恢复补丁本身不要求额外迁移；回滚客户端不撤销正式任务/交付。

V18新增companies.ai_authorization_revision、个人授权policy_revision及检索索引，保留已发布迁移不变。AI授权公司限制复用review_policy并经POLICY独立复核；公司生效边界通过共享/排他行锁与在途动作串行。旧授权失效后需本人重新开启，回退应用不得把已失效授权恢复。升级前备份，执行开关仍保持false。

解析缓存7天，完成事项原始私人材料30天，90天无活动先停后隐藏，每小时清理。主动删除立即停止私有读取/新动作，物理清理异步进行。未用于正式交付的私人检查作业/报告90天清理，正式交付引用的报告保留。正式任务/交付/制度附件及头像按用途保留，不级联删除正式业务。AI动作/授权审计365天后清理详情，保留操作者、类型、对象、时间和幂等回执；其他业务审计不受影响。个人授权创建与撤回同事务记录审计，同键重试不重复写入。

先关闭写入，核对租约、回执、任务和outbox，再按需关闭入口/OCR、切回旧UI。数据库只向前兼容，不DROP表、不删除正式业务。恢复备份时停止所有连接该库的API/worker，保持执行关闭，恢复删除标记/回执并核对后再开放。

`scripts/ai-work-deletion-markers.py` 通过数据容器本地psql导出和重放删除标记，不读取或输出密码。标记只有公司ID/事项ID/删除时间，必须独立于数据库备份保管，配置备份流程及定时任务持续导出，恢复前再导出一次；同一个文件合并已有标记，不能因恢复旧库覆盖新标记。恢复重放拒绝运行中的API容器，在单事务中重新隐藏事项、提高fence、停止待办、清除私有消息/计划/缓存/材料，保留正式文件与回执。部署者仍须停掉其他副本；本地容器检查不能证明集群已全部停止。最新标记文件丢失或未覆盖删除时间时，保持写入关闭并先补齐标记。

```powershell
python scripts/ai-work-deletion-markers.py export --container workpanel-backend-data-1 --database workpanel --file D:/private-backups/ai-work-deletions.json
# 将最新标记独立保存；恢复数据库时API应已停止。恢复后、启动API前执行：
python scripts/ai-work-deletion-markers.py apply --container workpanel-backend-data-1 --database workpanel --api-container workpanel-backend-api-1 --file D:/private-backups/ai-work-deletions.json
```

## 已记录验收与发布门槛

以下是2026-10-22的专项历史结果，基线main dc00e2b，后端/迁移提交5847b47、界面/续办92e6600，Issue #24 / PR #25；未在本次文档整理重跑。2026-11-05全仓自动化更新见 [统一验证入口](backend-validation.md)，不能用其替代供应商或设备专项。

| 范围 | 结果与证据 | 限制 |
| --- | --- | --- |
| 迁移恢复 | 原15份主线迁移逐份一致；390项旧回归通过，新迁移夹具首轮1失败/1错误，修正隔离schema后4项专项通过，不能写成首轮394全过 | 只转换已知旧历史的恢复副本；错误校验和/缺版本/失败/重复/未知脚本/非隔离目标拒绝 |
| 数据切换 | 68业务表与全部public序列摘要一致，原库不变，删除标记重放后正常Flyway V18启动；登录/能力/事项/任务/日志HTTP200 | 证据`output/ai-work-reconciliation/final-20261022-172125/`、`promotion-result.json`、`live-api-result.json`；不是当前在线检查 |
| 故障恢复 | 取消/删除/撤权/部分成功/回滚/模型OCR故障/预算各至少20次；真实JVM20轮40次终止，事件/回执/审计/outbox各一次 | `scripts/verify-ai-work-restarts.py`、`output/ai-work-restarts/result.json`；不把数据库时钟夹具称为进程重启 |
| 真实OCR/DeepSeek合成60场景 | 完整首轮55/60，退出1；修复后20份交付复验19符合预期，另1缺成本提前追问，补验55返回UNVERIFIABLE、19模糊图安全追问；跨轮次60场景均有预期证据 | 不是单轮60/60；生成器/验证器为scripts/ai-work-acceptance-corpus.py、verify-ai-work-corpus.py；`output/ai-work-corpus-reviewed.json` |
| 样本指标 | 跨轮次业务字段完成97.06%、提取字段96.81%、定位100%、追问31.67%、关键误写0、正式写入0；最新选定样本68797 tokens，中位14.392秒、P95 27.984秒 | 包含轮询/夹具，非纯OCR；四组82次供应商调用93394 tokens、余额约0.19元非精确账单；合成数据不代表生产准确率 |
| OCR隔离 | 锁镜像中文冒烟11.937秒、全文匹配/外连拒绝；文档OS沙箱探针与资源限制有证据 | 不证明OCR P95≤5秒，镜像重建须复验 |
| 客户端与Web | Flutter276通过/1跳过，分析/APK退出0；Web36通过/4失败/4跳过，定位修正后4通过/2跳过，累计40不同用例通过、4凭据依赖未验 | 不重复计数；历史双端创建/补充/恢复/删除为部分链路，不能等同三条完整Web闭环 |

历史样本错误、OCR冷推理中断、模型错误引用与空动作的失败日志保留，不能只留下成功轮次。证据位置主要为`output/ai-work-batch-*`、`output/ai-work-corpus-*`及`output/ai-work-reconciliation/`，仅为原执行机器的本地证据，丢失时应从Git/PR核对或重新验收，不能声称本机必然存在。

未完成：真实公司代表材料、多页/历史文件/同名完整矩阵、服务器20并发隔离性能、Android目标设备profile/TalkBack、5位首次使用者、双端真实并发写入/读屏、Web三条完整闭环、Sprint/分工/估算，以及规格同步/归档。保留tasks原复选状态。发布前配置独立删除标记保存与所有副本停写恢复；正式自动写入继续false，不因采样任务已勾选开放。
