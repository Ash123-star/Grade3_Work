## ADDED Requirements

### Requirement: Published migration lineage compatibility
系统 SHALL 保留主分支已发布的 Flyway V1–V15 原文，新增 AI 能力使用 V16–V18。P0 运维升级范围包括新库、主分支 V15 及已知的本地旧 AI 历史；旧 AI 转换 MUST 只在独立命名的恢复副本上运行，按完整已知脚本和校验和白名单校验，保留业务数据和原始安装信息，不在应用启动时自动 repair。

#### Scenario: Main database upgrades normally
- **WHEN** 新建库或已执行主分支 V15 的数据库使用新版应用
- **THEN** 正常 Flyway 前向迁移并校验通过，原用户、日志和评论不丢失

#### Scenario: Known unpublished AI history restored into a clone
- **WHEN** 已备份的本地旧 AI 数据库恢复到独立副本且完整历史匹配白名单
- **THEN** 转换工具只调整已执行脚本的版本及名称，补齐未执行的主分支迁移并正常校验，事项和正式业务保持，原库不改动

#### Scenario: Unknown history or original database target
- **WHEN** 目标不是隔离副本，或历史缺失、失败、重复、脚本或校验和不匹配
- **THEN** 拒绝转换，不修改业务内容，不将失败副本接入 API

## MODIFIED Requirements

### Requirement: DeepSeek jobs and maps
AI SHALL 由服务端 DeepSeek 生成带来源的结构化内容，支持流式状态、超时重试、取消、日预算、用量统计和输出校验；用户可在版本校验下编辑旧分析建议并维护地图关系，旧分析建议确认后才经过正常派发流程创建任务。新的办事执行器 SHALL 仅在用户当前权限与本次明确指令或有效预授权同时满足时调用白名单业务应用接口，关键修订仍独立复核，模型始终没有直接写库、扩大权限或代审批能力。自动动作 SHALL 有版本化计划、原子业务回执、幂等和审计，并在读取、执行和历史输出时重新鉴权。

#### Scenario: Provider unavailable or injected log text
- **WHEN** DeepSeek失败或日志/截图/制度文件含越权指令
- **THEN** 基础业务继续运行，文件指令只作为数据，AI不直接写业务且不扩大数据范围；办事输入保留，不生成虚假执行回执

#### Scenario: Authorized direct work request
- **WHEN** 用户明确要求创建任务，或其有效预授权允许当前范围内的创建动作，且服务端业务校验全部通过
- **THEN** 执行器经普通任务应用接口办理并返回真实回执，不要求对同一已授权步骤再次确认

#### Scenario: Old analysis is not a new command
- **WHEN** 用户查看旧分析建议、重试旧AI作业或仅上传资料但没有执行指令/有效授权
- **THEN** 不自动派发正式任务，新执行接口不能把旧建议、文件指令或模型文本当成用户授权

#### Scenario: Permission loss and duplicate execution
- **WHEN** 执行前用户权限变化，或双端重发同一动作
- **THEN** 按当前权限拒绝失权写入，合法重复仅返回同一原子回执，不重复创建任务或绕过独立审核
