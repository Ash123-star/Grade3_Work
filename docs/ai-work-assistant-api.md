# AI办事接口 v1

交付核对规则升级为 delivery-rules-2：只按独立的“字段：值”标签匹配，标题提及相同词不算字段；重复字段、公式或不清晰内容仍不能通过，旧规则报告因快照变化需重新检查。用户已从任务入口选定对象并明确只检查时，模型空动作/无追问会补建只读检查，不能仅凭文字答复显示检查成功，也不会隐含提交。

2026-10-22 本批接入 main 的日志窗口、公开评论回复和管理员审计契约。Flutter 使用原公共路径；独立 Web 办事使用 `/api/admin/workspace/ai/work-*`，附件及只读任务/制度详情也使用明确白名单的管理员别名。服务端每次重新校验 ADMIN 和原业务范围，管理员仍不能读取他人的私人事项；SSE 别名同样传递 Authorization、Last-Event-ID。OpenAPI 快照已由真实运行服务导出。

正式来源由服务端绑定：匹配动作的工作流及制度查询取得的有效资料，即使模型漏报 sourceIds 也会进入冲突检查。相同范围/工作流的无法证明兼容的规范要求停止办理；常见差旅、报销、发票用词会归一后检查。`sources` 只包含正式制度，已提取附件被模型误放进 sourceIds 时从制度引用中剔除，仍保留 fileHashes 与材料定位；陌生来源 ID 继续报 AI_SCHEMA。金额/数量同值同单位才能进入候选要求。任意隐含语义冲突仍需人工核对。

日志详情新增 submittedAt/editableUntil/canEdit/canWithdraw，由客户端直接使用能力字段。`POST /logs/{id}/withdraw` 要求 version/reason，保留首次提交时间；首次提交不足24小时才允许编辑/撤回，管理员也不能越过窗口。评论支持 parentId，返回 parent_id/author_name，重复 POST 会新增评论，客户端禁止自动重试。Flutter 已接入撤回、能力展示和回复参数；独立的回复选择交互尚未新增。

2026-10-22补充：计划可包含最多10个动作，新建任务单批最多5项；超出时保留请求并询问本批选择，不静默截断。人员和日期缺项一次汇总，计划动作的`evidence`保存核实原句；该字段不进入正式任务参数。多个已有任务按各自动作的用户原句定位，模型提供的taskId不能改换目标；无法唯一定位时等待补充。来源冲突比较同范围有效资料，不因标题不同跳过重叠约束。

`DELETE /ai/work-items/{id}` 在实时身份校验后按原键/版本返回删除受理回执，首次执行仍需本人当前事项；同键不同版本409，其他身份不能读取该回执。入口关闭在步骤提交前再次检查，停止之后的动作不撤销已提交任务。

提交结果不明时状态为`RECONCILING`，客户端显示“正在核对结果”；期间不执行其他步骤、不提供盲重试。服务端持事项/步骤锁核对同事务动作回执，一致则仅恢复原结果；确定无回执才重排未提交步骤，保留尝试上限。指纹不一致保留核对状态并允许停止，普通日志不输出私有正文。

结果仍不明时，`POST .../messages` 返回409 `OUTCOME_PENDING`，原消息、材料和回执保留，避免新指令重做未核对动作。取消/删除会同时停止UNKNOWN步骤并推进fence，已提交的正式任务与交付保留。核对耗尽后按真实回执区分FAILED/PARTIAL；未知结果不当作前置失败传播。当前核对证明仅适用于同一数据库事务内的业务和回执，新增外部副作用不得直接复用该重试路径。

未接入的报销/采购/请假等申请仍需在相应业务系统提交；单纯申请不能变成模型猜测的任务动作，模型自称的申请编号或已提交文案不会作为办理结果。有动作计划的答复只说明要求已整理，“已创建/已提交”由真实业务回执提供。

本批补齐：`POST /procedures/{id}/template-files/{file}` 接收 `version/reason`，只读预填并下载当前正式模板的 DOCX/XLSX 附件。姓名/部门/日期来自服务端，未知字段和公式保留；拒绝审核人/身份覆盖，返回 `application/octet-stream`、受保护文件名和 `Cache-Control: no-store`。每次重查资料范围/附件绑定，并在解析后再次检查身份和来源版本；撤回404、版本变化409、不支持格式400，无业务副作用，不要求幂等键。

待确认事项的办理条件失效后可使用原 `retry` 命令重新核对，无需重抄已知信息。已成功动作保留回执；未变化且仍有效的逐动作授权可复用，过期或目标/来源/人员变化的动作重新确认。确认只包含待确认动作，选择有依赖动作时须同时选择其尚未成功的前置动作，否则400 `DEPENDENCY_REQUIRED`；消费确认失败时整个事务回滚。执行只复核当前动作，已成功动作的对象后续修改不阻塞其他动作。正式资料消费与发布/撤回使用公司范围共享/排他事务锁，并锁定相关资料，避免新冲突资料在校验与提交间插入。

变更 `ai-work-assistant`，根路径 `/api`。复用 Bearer 会话与 `{code,message,traceId}` 错误。事项响应带 `contractVersion=1`。私人事项仅本人可读，管理员无额外读取权。

Flutter和Web在REST边界验证契约版本、事项id/正整数版本、已知状态及消息/回执结构，未知或损坏响应提供刷新入口，不转换为空列表或成功（Flutter使用本地`WORK_INVALID_RESPONSE`）。分页使用服务端nextCursor，重复id保留较新版本；Web刷新重读已展开页，游标未推进或响应失败时保留既有历史。补充/确认/取消/续办互斥；相同未确认请求重发保留键，动作、请求版本或选定对象变化后换键，409立即重新GET并保留输入。命令401/403/404立即清正文，不依赖错误正文必须为JSON；账号变化后废弃旧响应并阻止旧repository继续提交。删除仅在id/state=CANCELLED回执匹配后离开页面。Web能力读取失败暂停发送并保留材料，不把浏览器原始异常或供应商正文展示给用户。

| 方法/路径 | 参数与边界 |
| --- | --- |
| GET `/ai/work-capabilities` | 当前权限、入口/写入/OCR真实开关、文件限值；不返回凭据 |
| POST `/attachments?purpose=AI_WORK` | 登录成员主动上传私有AI材料，multipart字段file；签名/扩展名/大小/图像头尺寸提前校验。省略purpose保留通用附件兼容；不自动分享，不保证上传幂等，后续事项命令使用幂等键 |
| GET `/ai/work-items?cursor=0&limit=30` | 本人分页，nextCursor=-1结束 |
| POST `/ai/work-items` | text或attachmentIds，选填taskId/taskVersion；幂等键必需，202仅表示保存 |
| GET `/ai/work-items/{id}` | 消息、计划、步骤、回执、eventsCursor；实时鉴权 |
| POST `.../messages` | version/text/attachmentIds，选填taskId/taskVersion与answers={ownerId}；幂等键必需，选人ID实时校验 |
| POST `.../confirm` | version/planVersion/planHash/confirmationId/actions，actions为stepKey数组；幂等键必需，10分钟内一次消费 |
| POST `.../cancel`、`.../retry` | version与幂等键，停止后续或仅重试失败；不删除正式业务 |
| DELETE `/ai/work-items/{id}` | If-Match整数版本与幂等键，202停止并隐藏私有内容；物理材料异步清理 |
| GET `.../stream` | SSE change只含版本与持久序号；Last-Event-ID非负十进制且不得超前，否则400 INVALID_CURSOR；每用户最多3流，429 STREAM_LIMIT；refresh无id表示重新GET，access-lost仅含status(401/403/404)并关闭，客户端清缓存 |
| GET/POST `/ai/work-authorizations` | 默认无授权，action=CREATE_TASK/SUBMIT_DELIVERY；scope={ownerIds/taskIds,maxActions?}，对象≤100、每批≤5，expiresAt≤30天且受公司上限约束；列表effective表示当前是否生效 |
| GET `/ai/work-authorization-policy` | 已确认成员读取本人可用动作canCreate/canSubmit、maxDays/maxObjects/maxActions及version/revision；只读不授予权限 |
| POST `/organization/review-policy/revisions` | 管理员提交version/reason和aiWorkCreateAuthorization/aiWorkSubmitAuthorization/aiWorkAuthorizationMaxDays(1..30)/aiWorkAuthorizationMaxObjects(1..100)/aiWorkAuthorizationMaxActions(1..5)，沿用POLICY独立复核；生效使旧个人授权失效，再放宽也不恢复 |
| GET `/ai/work-authorization-options?action=&search=&cursor=0` | CREATE_TASK返回受权人员姓名/部门/团队；CHECK_DELIVERY返回可读任务；SUBMIT_DELIVERY仅当前可提交任务，30项分页 |
| POST `/ai/work-authorizations/{id}/revoke` | version与幂等键；撤回与写入按用户锁串行 |
| GET `/procedures?search=&drafts=false&cursor=0&limit=30`、`/{id}?draft=false` | 当前有效且适用正式资料；中文词/英文词受权检索排序，items/total/nextCursor，limit1..100；管理员才能读取维护稿 |
| POST `/procedures` | title/type/content/scopeKind/scopeId/effectiveFrom/effectiveTo/attachmentIds/workflow/acceptanceChecklist与幂等键 |
| POST `/procedures/{id}/revisions` | version/candidate与幂等键；旧正式版本继续有效 |
| POST `/procedures/{id}/publish-requests` | version/reason/withdraw与幂等键；独立PROCEDURE复核，无独立审核人不生效 |
| GET `/procedures/{id}/comparison` | 管理员比较正式版本与维护稿，未发布时published为空 |
| POST `/procedures/{id}/template-draft` | version/reason；服务端填姓名/部门/日期/事由，未知占位保留；不改二进制文件、不提交业务 |
| POST `/procedures/{id}/template-files/{file}` | version/reason；下载当前正式版本绑定的DOCX/XLSX安全预填副本，解析后再次校验身份/版本，octet-stream、no-store；不改变原文件，无业务写入，不要求幂等键 |
| POST `/tasks/{id}/delivery-checks` | taskVersion/attachmentIds与幂等键；202返回持久作业ID，后台处理 |
| GET `/tasks/{id}/delivery-checks` | 恢复本人最近一次检查作业/结果 |
| GET `/tasks/{id}/delivery-checks/{id}` | QUEUED/RUNNING/FAILED作业状态或最终报告；成功后id为真实报告ID，兼容直接读取报告ID；每次重查任务/规则/制度/材料快照，失效返回STALE、snapshotValid=false并隐藏旧核对项，不能提交 |
| POST `/tasks/{id}/deliveries` | taskVersion/checkId/checkVersion/attachmentIds/mode/text与幂等键；CHECKED要求PASS；主动MANUAL不能绕过必交材料 |

任务acceptanceChecklist最多30项，支持id/title/category/required/fileName/field/expected/unit/currency/source。INFERRED强制required=false，无清单或只有推断项不能整体PASS。逐项状态PASS/NEEDS_FIX/UNVERIFIABLE/NOT_APPLICABLE；金额使用BigDecimal并核对币种和单位。正式交付同事务重查参与角色、阶段、任务/报告版本、文件hash，绑定文件、执行FEEDBACK、写回执/审计/outbox，失败全回滚。检查、提交、人工验收分别记录，AI不代验收。

资料维护列表 `drafts=true` 同样按最新维护稿标题搜索并分页，单项附带当前版本的 `pending_review_id/review_status`；待审时可查看独立复核申请，停止重复申请发布。维护稿未正式通过前不能由普通成员读取，不进入正式检索。

个人限定授权的创建和撤回会同事务写入 `AI_WORK_AUTHORIZATION/AI_WORK_AUTHORIZATION_REVOKED` 审计；同键重放不新增审计。365天后清理该类审计与AI动作审计的详情，保留操作者、对象、类型、时间和幂等回执；其他业务审计不受影响。独立运维CLI导出/重放删除标记的使用和维护条件见部署文档。

文字≤10000，每次≤5文件、单个≤10MB、总≤30MB。PNG/JPEG/PDF/DOCX/XLSX签名识别；PDF≤50页、图像≤20MP、表格≤50000格、ZIP展开≤100MB。文档独立256MB子JVM、30秒硬超时；扫描PDF全文件90秒前后检查、单次OCR30秒，超限拒绝保存为成功。公式、签章和低置信内容无法核实。缓存按company+owner+hash+parserVersion隔离7天。

`limits`统一返回text/files/fileBytes/totalBytes/formats/pdfPages/imagePixels/renderPixels/spreadsheetCells/zipEntries/expandedBytes/extractedParts/extractedCharacters。格式为png/jpg/jpeg/pdf/docx/xlsx；ZIP最多20000条，提取最多50000片段、500000字，扫描渲染每页≤16MP。上传和AI接入执行同一基础策略，隔离子进程继续校验OOXML实际内部类型、PDF页数、单元格和解压限额；宏、嵌入对象、外部关系和PDF主动内容拒绝。415 UNSUPPORTED_FILE/FILE_TYPE_MISMATCH、400 FILE_LIMIT、422 FILE_UNREADABLE/FILE_ENCRYPTED/FILE_UNSAFE；HTTP文件过大仍可由multipart层返回413 FILE_TOO_LARGE。两端读取同一能力限值，不展示内部解析异常。

自动写入关闭时PREPARE及CHECK_DELIVERY仍可生成私人检查报告，SUBMIT_DELIVERY等正式动作继续暂停。用户明确只检查时，服务端将模型提交候选收窄为检查，即使存在匹配长期授权也不提交。不通过/无法核实保留报告并等待补材料；人工核对只能由用户主动在交付入口选择并填写说明，已确认硬性缺项仍拒绝。提交重验当前解析器版本，旧版本通过报告须复检。

用户本次明确“不要提交”“停止办理”“只整理”等要求时，长期授权不能覆盖禁止指令；模型仍建议写入也不会生成可执行写步骤。仅检查反馈内容属于检查，不因出现“反馈”二字视为提交要求。

日期以Asia/Shanghai解释本次用户文字里的今天/明天/后天和明确数字时刻；截图、旧聊天、引用及“下班前”等模糊描述继续追问。确认绑定当前权限、来源、人员/任务版本、文件hash及期限，新消息不重复已有回执的动作。

办理已有任务时，目标取自用户在任务入口/选择器选定的对象，或本次文字明确提到的完整任务名/ID且仅命中一项当前可读任务。模型返回的taskId不能改换该对象；无目标、重名或同时提到多项时集中追问，不从截图指令或旧聊天猜测目标。转派负责人同样执行同名消歧。

计划action的similarTasks最多3个当前可读同负责人相似任务，提供id/title/version/deadline。出现候选时不自动新建；用户可打开原任务，或确认仍然新建，绝不自动合并。匹配仅检查最近100个标题词候选，不保证发现全部语义重复。sources携带标题、版本和excerpts={locator,content}，定位使用发布原文行/段；输入只发相关脱敏摘录，模型引用限于本次提供集合。同级同标题正文差异或同流程稳定清单项矛盾会列出双方依据并阻止写入，其他隐含语义冲突仍须人工核对。

400格式错误，403/404无权，409版本/计划/报告失效或同键异内容，415格式不支持，422无法读取，429预算/限流，503供应商/开关关闭。客户端使用自然错误文案，不显示内部异常和供应商响应。截图不随任务自动分享，AI无审批通过、验收、归档、外发、删除正式业务工具。写入开关默认false，确认保存不代表正式业务已执行。

事项 GET 的正文和 eventsCursor 来自同一个 PostgreSQL 可重复读快照。SSE 序号是当前事项的持久事件序号（允许不连续），只接受递增值，重复/乱序不刷新；refresh 不推进该游标，同版本仍须重新 GET 以清除失效来源。流每批重新验证会话/成员及事项归属，失权时 access-lost 后结束。两端收到失权后清空私人正文、输入、材料与选项，账号/页面切换废弃旧请求。Web 使用 fetch 流发送 Authorization/Last-Event-ID 请求头，禁止 token 查询参数；断流自动重连、回到前台重新 GET，低频轮询作兜底。

AI_WORK_UPDATED 通知在进入 WAITING_INPUT/WAITING_CONFIRMATION/FAILED/PARTIAL/SUCCEEDED 的状态事务中写入，稳定键 ai-work-state:{workId}:{workVersion}；同状态刷新、处理中、等待复核不新发。outbox 投递复用相同通知 id，重复投递无重复通知。此变更不修改已发布迁移，已有通知保持原记录。
