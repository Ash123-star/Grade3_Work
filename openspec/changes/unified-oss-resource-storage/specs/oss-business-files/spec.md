## ADDED Requirements

### Requirement: Unified private OSS business file storage
优先级P1，范围为头像、任务附件、成果交付、AI材料、制度流程及模板原文件。服务端 SHALL 将新文件正文写入私有 OSS，数据库仅保留元数据和业务引用；成功响应 MUST 以 OSS 对象完成校验且元数据 READY 为条件，保留既有附件ID契约和文件大小/格式校验，存储配置不完整时不得静默写回数据库。

#### Scenario: Upload and retrieve each supported purpose
- **WHEN** 已确认成员上传合法文件并用于任一合法用途
- **THEN** OSS保存原始字节，授权下载返回相同SHA-256及大小，AI解析及模板读取从统一存储端口取得同一正文，OSS READY记录不再保存bytea正文。

#### Scenario: Invalid input or OSS unavailable
- **WHEN** 文件为空、超过适用限额、AI格式伪装，或OSS超时/拒绝写入
- **THEN** 返回明确的校验或503存储错误，不返回可用附件成功结果，不生成正式业务绑定，残留上传意图可追踪并恢复/补偿。

### Requirement: Authorization precedes object access
优先级P1，范围为Android、Web及AI内部读取。服务端 MUST 在对象存取前验证当前会话、确认状态、公司和业务数据范围，保留私人材料、头像、任务、制度和交付各自访问规则；客户端和普通日志 SHALL 不包含OSS密钥、签名或公开业务URL，管理员不得自动读取私人AI材料。关键修改仍使用版本及独立复核。

#### Scenario: Reject revoked or out of scope access
- **WHEN** 待确认、停用、跨公司、组织范围外用户或无私人材料权限的管理者请求文件
- **THEN** 双端收到相同权限错误，不读取或泄漏OSS对象信息，不扩大AI检索范围。

#### Scenario: Revisions do not publish candidate files prematurely
- **WHEN** 用户提交含新附件的关键修订、申请人尝试自审或最终批准时业务版本已改变
- **THEN** 沿用自审拒绝和版本冲突规则，旧有效版本及其附件继续生效，新候选附件不提前向无权用户开放。

### Requirement: Generated outputs use protected OSS storage
优先级P1，范围为统计CSV和模板预填DOCX/XLSX。服务端 SHALL 先将输出写入OSS，记录所有者、公司、来源和版本、哈希、大小及期限，再从OSS交付文件；原接口保留二进制响应，新增产物下载 MUST 在当前身份及所有来源仍有效时才允许读取。生成文件默认24小时过期，可由部署配置调整；导出继续使用详情相同数据范围及公式注入防护。

#### Scenario: Export and template preparation round trip
- **WHEN** 合法用户从任一客户端导出范围内记录或生成有效模板预填文件
- **THEN** 产物可在OSS核对，原下载入口获得一致字节，新的受控产物入口允许本人在来源仍授权且未过期时读取。

#### Scenario: Sources revoked or expired
- **WHEN** 来源制度撤回/版本变化、导出中任一记录已越权、用户调岗/停用或产物过期
- **THEN** 拒绝后续下载，生成期间发生变化也不得交付旧产物，其他用户无法凭产物ID下载。

#### Scenario: Temporary output cannot become a permanent reference
- **WHEN** 用户将生成文件ID作为任务、制度流程、头像或正式交付附件提交
- **THEN** 服务端拒绝绑定，临时产物仍遵循原来源权限及有效期，不能用永久引用绕过过期清理。

### Requirement: Recoverable historical migration
优先级P1，范围为已有DATABASE附件。迁移工具 MUST 提供dry-run、分批、可恢复和重复执行能力，上传并读回验证哈希/长度后才切换存储引用，保持附件ID、业务引用和版本不变；失败时旧文件继续可用。清除数据库副本 SHALL 作为经备份及报告核对后的独立步骤，已过期或删除文件不得被恢复。

#### Scenario: Migration interrupted and resumed
- **WHEN** 上传后或切换前进程中断，随后恢复运行
- **THEN** 工具核对现有对象与元数据，重试未完成项且不重复破坏成功项，旧入口继续返回正确字节，生成成功/失败/跳过报告。

#### Scenario: Historical file changes during migration
- **WHEN** 上传读回哈希不一致，或文件在迁移期间被清理/元数据版本变化
- **THEN** 不切换该行，不覆盖新版本，不删除有效数据库副本，记录可定位错误。

### Requirement: Durable compensation and deletion
优先级P1，范围为上传补偿、AI原件、临时产物及派生缓存。系统 SHALL 用持久化意图和幂等任务协调数据库与OSS，清理先锁定并重新验证所有正式引用，再拒绝新读写绑定并排队删除；失败重试且404视为已删除。正式任务、交付、制度或头像仍引用的原件 MUST 不因私人AI事项清理被删除。

#### Scenario: Object write succeeds but metadata commit fails
- **WHEN** OSS已写入但READY提交失败
- **THEN** 不返回上传成功，持久化意图可在重启后核对恢复或删除对象，不留下不可追踪的公开对象。

#### Scenario: Delete fails or races with binding
- **WHEN** OSS删除暂时失败或同时发生正式附件绑定
- **THEN** 删除任务可重试，锁/版本决定唯一有效结果，正式引用成功的对象保留，已进入删除状态的对象不能再绑定，数据库不先宣告物理删除成功。
