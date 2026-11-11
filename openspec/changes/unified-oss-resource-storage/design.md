## Context

实施基线更新：2026-11-11 已从GitHub获取最新 `origin/main`（3f9eb2d），并快进至包含其全部提交且与线上一致的 `origin/fix/53-notification-refresh`（aa70b35），保留消息缓存/条件请求优化。独立工作树分支 `feature/79-unified-oss-latest` 只承载OSS变更，原工作区用户改动保留。以下现状调查来自最初19db6f3基线；实际整合保留新版AnalyticsQuery/Repository同范围导出与ProfileService/Repository分层，新增迁移采用V31，不占用已发布V22–V30。

整合编号更新（#82）：上述 V31 是独立 OSS 分支的历史编号。三条功能分支整合后，当前 OSS 迁移为 V33；V31 用于每日事项范围/颜色，V32 停用创始人互审。已发布 V1–V30 不变，升级及开发库历史核对要求见 docs/database-schema.md，本轮验收见 docs/backend-validation.md。

2026-11-11 用户确认使用已有私有业务 Bucket `panduola-work`，地域华北2北京（`cn-beijing`），Endpoint `https://oss-cn-beijing.aliyuncs.com`，范围包含内置图标和插画。凭据、Bucket 实际 ACL、网络与 RAM 权限尚未验证。

现有 `AttachmentApplicationService` 用数据库保存并返回二进制，下载在读取时重新鉴权；`FileExtractor`、`DeliveryService`、`WorkService` 和 `ProcedureTemplates` 经该服务读取字节，但依赖 `data` 形态。`WorkRetention` 用 `octet_length(data)` 识别已清理材料。统计 CSV 和模板预填文件即时返回，没有持久化。Flutter 两个共享素材组件文件集中使用 `Image.asset`、`AssetImage`、`SvgPicture.asset`；许可证通过 `rootBundle` 注册。迁移最高 V21，不能改动已有迁移。

开始时分支为 `chore/public-backend-address`，工作区含用户的后端地址、移动端详情、网络配置、图片删除和日历提案等改动。本变更新建规划目录；不提交或覆盖原有改动。实施前关联 Issue 并建立独立功能分支/工作树，安全分离本次修改后才提交。

## Goals / Non-Goals

**Goals:** 所有上传/生成文件和运行时静态素材存入 OSS 并在实际业务读取；历史文件 ID 不变；业务私密性、版本冲突、AI 文件限额和清理语义不变；支持可恢复迁移、可审计清理、双端加载缓存和真实 Bucket 验收。

**Non-Goals:** 不将数据库记录、应用代码和操作系统必需的安装资源替换为网络文件；不开放私有文件直链，不把业务文件改为公共读，不改审核策略、AI 模型和业务状态机。Android 桌面图标、原生启动图、必要字体/署名及离线降级可保留打包副本，但也同步 OSS，运行时可远程加载部分优先使用 OSS。

## Decisions

### 1. 私有 OSS 与服务端存储端口

| 路线 | 优点 | 代价/判断 |
| --- | --- | --- |
| 数据库 bytea | 单库事务简单 | 不符合用户统一 OSS 的目标 |
| 私有 OSS，后端代理上传下载 | 复用逐次鉴权、无客户端密钥、双端契约兼容 | 增加后端流量；本期采用 |
| STS 直传及签名下载 | 降低后端流量 | 引入客户端凭据、跨域、回调及授权撤回窗口；本期不采用 |

在 attachment 基础设施增加 `ObjectStorage`（put/get/head/delete）及阿里云官方 Java SDK 实现；版本以实施时官方兼容信息锁定，不自行手写签名。对象 Key 使用服务端生成的 ID，按 `workpanel/business/{companyId}/{attachmentId}` 与 `workpanel/static/{release}/{hash}/{logicalPath}` 分离，不含原文件名、姓名等个人数据。Bucket 保持私有，匿名静态接口只能访问已发布清单内的静态 Key。所有读写使用 HTTPS、连接/读取超时、有限重试及限制字节数；超限、Hash 不符或存储不可用明确报错，不假装成功。

配置增加 `OSS_BUCKET`、`OSS_REGION`、`OSS_ENDPOINT`、`OSS_PREFIX` 及服务端凭据链；推荐运行角色/短期凭据，也兼容服务端环境变量 AccessKey 与 SecurityToken。客户端只知道后端地址和静态版本；日志不输出凭据或签名。配置缺失时报告存储不可用，不能把新文件静默回退数据库。测试通过注入存储替身运行，真实 OSS 验收单独记录。

### 2. 元数据、写入与补偿

新增 Flyway 迁移，使 `attachments` 支持 `storage_provider`（历史 DATABASE / OSS）、`object_key`、`size_bytes`、`storage_state`（PENDING/READY/DELETING/DELETED）、`storage_version`，保留 `file_hash` 和现有所有者/公司/关联。OSS READY 行不保存数据库二进制；历史 DATABASE READY 行在迁移完成前继续兼容读取。约束确保 READY 有唯一有效存储来源；显式状态替代所有 `octet_length` 判断。

采用持久化上传意图：独立短事务提交 PENDING 元数据和唯一 Key → 上传 OSS → 校验长度及 SHA-256 → 事务置 READY → 返回原上传响应。上传失败不返回附件成功；上传后数据库提交失败的 PENDING 对象由可恢复任务核对后完成或删除。业务绑定只能引用 READY 且未过期附件。清理和绑定使用同一元数据行锁/版本，避免对象清理与正式引用竞争；不在数据库长事务中无限等待网络。

`AttachmentApplicationService` 区分授权元数据查询与取字节；只有授权完成才调用存储端口。现有 `read/owned/intake` 调用按需适配，不直接把 OSS SDK 注入 AI/任务模块。头像保存、任务绑定、制度绑定也校验可用状态和期限。

### 3. API 与生成文件

现有 `POST /api/attachments` 和 `GET /api/attachments/{id}` 保持输入/输出、1字节–10MB 普通附件限制及 AI 文件策略，新增存储失败码 `503 STORAGE_UNAVAILABLE`、不存在对象 `404 FILE_NOT_FOUND`、校验不一致 `502 FILE_INTEGRITY_ERROR`；API 全部保留统一错误 envelope/traceId。下载仍返回二进制和安全文件名，不返回公开 URL；鉴权前不探测对象存在性。响应含 `nosniff`，私有文件禁止共享缓存。

新增生成文件应用服务和 `GET /api/generated-files/{id}`；需要当前 ACTIVE 身份且公司一致、所有者一致，再验证生成时记录的来源仍在当前范围内。生成元数据保存输出类型、来源记录 ID/版本/所需范围、哈希、大小及期限，不存文件正文。CSV 保存完整来源 ID 清单，后续读取逐项核对当前可见性；模板保存资料/版本/附件及当前权限指纹，任一来源失效则拒绝旧产物。

原导出和预填接口仍返回文件字节以兼容双端，但先持久化 OSS 并读回，返回前重新校验权限及来源版本。生成文件默认保留24小时，可配置，期限到后先拒读再删除对象。生成是只读业务操作，无业务状态变化；重试可产生新产物，不承诺原接口幂等。导出继续复用现有数据范围、上限和 CSV 公式注入防护。接口注释、运行时 SpringDoc、`docs/openapi.json`、`docs/backend-interface.md` 同步更新。

### 4. 静态素材发布与双端使用

发布工具盘点 `mobile/assets`、Web 实际引用文件和原生图标/启动资源，以及通过实际Flutter构建准备的依赖包图片、Material/Forui图标字体、Inter字体、FontManifest与依赖许可证，输出逻辑路径、类型、大小、SHA-256、版权来源、用途（运行时/原生打包/离线降级）。运行时资源保持 `assets/`、`packages/`、`fonts/` 原逻辑Key；缺少完整Flutter准备目录时拒绝仓库发布，避免漏发依赖素材。拒绝目录穿越、符号链接越界、密钥/环境文件和非白名单类型；许可证文件作为资产同步，包内HTML执行入口和着色器仍随代码发布。

逐文件上传后读回校验，只有整版校验完成才切换数据库中的当前发布版本。旧版不可变、暂保留；并发发布使用版本比较，冲突返回409且旧版继续生效。发布由部署运维凭据执行，不增加普通员工发布权限，不取代业务制度的独立审核。

增加 `GET /api/assets/manifest` 和 `GET /api/assets/{release}/{logicalPath}`，用于登录前图标等公共产品素材；后者只允许已发布清单的准确路径、合法 MIME、尺寸和哈希，不接受 Bucket/Key/URL 参数；不存在和越界404。按内容哈希缓存不可变素材，manifest 支持 ETag/304，失败不激活半版。

Flutter 增加统一素材加载器，替换集中图片/SVG/纹理引用，启动时受限等待 manifest 并通过 FontLoader 加载远程字体，使用磁盘/内存缓存及并发控制；失败用最后已验证缓存或打包降级资源，保持布局和语义。桌面图标和操作系统启动资源继续使用必要打包副本；此为平台技术限制，不宣称已改成网络启动。保留字体授权和应用内许可证可用性。Web 对实际存在的图像/字体引用使用同清单；JS/CSS 构建入口继续由应用发布。双端离线时可运行并明确区分缓存/降级证据和真实 OSS 命中证据。

### 5. 清理、迁移与权限

业务文件保持现有公司/所有者/任务/制度/交付访问逻辑，上级或管理员不会因角色获得私人 AI 材料访问权。待确认、停用、跨公司和范围缩减即时拒绝。任务创建和关键修改仍走既有复核；候选附件不提前对审核范围外用户开放，申请人不能自审。

清理事务先重新核对正式引用、设置 DELETING 并写持久化删除任务；提交后任务幂等删除 OSS 对象，404视作已删除，失败保留重试。DELETING 不能新增绑定，正式引用与清理通过元数据锁竞争。完成后标记 DELETED 并清理派生缓存，避免只清空数据库却遗留 OSS 原件。保留 AI 原有30/90天规则，不按整个 Bucket 的粗粒度生命周期误删正式文件；生成文件另有24小时期限。

## Risks / Trade-offs

- 私有 OSS 后端代理增加带宽/延迟 → 图片版本缓存、适度并发、大小和超时限制；不承诺尚无证据的性能指标。
- 对象和数据库无法同事务 → 持久化意图、显式状态、幂等补偿、周期核对；故障注入验证每个断点。
- 静态接口误读业务对象 → 白名单清单和严格前缀隔离；IAM 最小权限；测试路径穿越和伪造版本。
- 素材远程化导致冷启动依赖网络 → 受限等待、完整性校验缓存和打包降级；平台必需资源保留副本。
- 混合工作区和迁移编号竞争 → 保留原改动，实施前复核版本及隔离工作分支；未经核对不推送。
- 当前尚无真实 OSS 调用证据 → 不勾选真实验收，不报告迁移或上线完成。

## Migration Plan

1. 关联 Issue/Sprint/负责人，隔离本次修改；只新增迁移，备份当前数据库并记录附件数量及哈希清单。
2. 部署兼容 DATABASE/OSS 读取的新代码，校验 Bucket 私有、凭据权限及测试前缀读写；新上传统一写 OSS。
3. 静态发布工具 dry-run 列清单，完整上传并校验后激活版本，接入双端实际资源调用。
4. 历史迁移按附件 ID 分批，记录迁移意图，上传、读回比较哈希/长度；在锁及存储版本一致时切换 provider，失败留原数据并重试。已清理文件不恢复；历史 ID、引用和业务版本保持不变。
5. 每批核对成功/失败/跳过、引用和对象完整性；确认全量迁移后才启用独立的数据库副本清除步骤，清除前必须有备份和迁移报告。重复运行不重写有效已迁移文件。
6. 回滚静态版本指针并保留旧版素材。应用回滚只能到支持 OSS 的兼容版本；需要回到仅支持 bytea 的旧版本时，先停写并从 OSS 全量校验恢复数据库二进制，不能直接回滚迁移或删除 Bucket 对象。
7. 统一验收后保留测试报告及真实 OSS 证据；安全处理独立提交、推送和 PR。当前混合用户改动未解决前不自动推送。

## Open Questions

- 服务端 OSS 凭据的实际配置位置、角色或 RAM 权限、Bucket ACL/网络是否可用，实施和真实验收前确认；不在聊天索取密钥。
- Issue 编号、Sprint 和估算待关联；当前仅有本地规划，不伪造远程 Issue。
- 静态全量清单、字节总量和实际发布版本在发布工具 dry-run 生成；不得只迁移少数展示图片就报告“所有资源”。

## Verification

规划执行 `openspec.cmd validate --all --strict`。实现结束集中运行 `powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1`（必要时 `-DockerMaven`）、`flutter analyze`、相关 Flutter 测试和 Web 构建/测试，保留退出码。新增存储/迁移/补偿单元测试，真实 PostgreSQL + 可控存储替身的 HTTP 链路覆盖全部文件用途；替身不算真实 OSS 验收。使用用户 Bucket 下独立测试前缀跑上传→绑定→授权下载、AI解析、模板预填、导出、静态清单→实际渲染及删除，比较哈希并记录请求结果，不记录凭据或私人正文。验证安全隔离和故障恢复两项非功能要求，并记录加载缓存及冷启动耗时。
