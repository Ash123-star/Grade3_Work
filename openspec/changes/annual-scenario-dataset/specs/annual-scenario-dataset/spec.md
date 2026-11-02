## ADDED Requirements

### Requirement: Fresh annual scenario dataset
P0：系统 SHALL 在显式启用annual-2026数据集时，通过同一DataSource与独立Flyway历史在空业务库生成2026年6—11月数据。现有正式与旧场景迁移 MUST 保持原样，默认路径保持兼容。

#### Scenario: Fresh database and repeated startup
- **WHEN** 新库完成正式迁移并配置合格密码，随后启动两次
- **THEN** SHALL 首次生成关联场景，第二次跳过且不重复或重置密码

#### Scenario: Nonempty or invalid target
- **WHEN** 已有业务/其他人员/旧场景或账号冲突，或者密码未满足12字符和72字节限制
- **THEN** MUST 拒绝场景初始化，不能删除或覆盖已有业务

### Requirement: Staggered tasks and truthful logs
P0：18名正常场景成员 SHALL 各有至少5条任务，任务有角色职责、多样起止日期、Mock五色标签与同事交接。公司 SHALL 有10条有效重点。日志 MUST 按人按日唯一并关联本人参与任务，不生成未来提交或入职前日志。

#### Scenario: June to November calendar
- **WHEN** 查询已入职成员6—11月排期
- **THEN** SHALL 呈现短任务、交叉任务、空白日期及少量跨周/跨月任务，11月未来任务无伪造完成事件

#### Scenario: Pending, disabled and other company
- **WHEN** 查询待确认、停用或其他公司成员
- **THEN** MUST 保留相应权限限制，待确认无业务任务、停用只留历史，隔离公司任务不关联主公司

### Requirement: Short usable test credentials and rebuild instructions
P0：账号 SHALL 使用至少3字符合法短名，密码 SHALL 从环境传入并满足现有正式策略。部署说明 MUST 保留原systemd/数据库实例，采用新空库切换并说明回滚和未验证边界。

#### Scenario: Cloud rebuild
- **WHEN** 运维按说明新建库并启动新版JAR
- **THEN** SHALL 可运行正式迁移与年度初始化，旧库保留；错误时可恢复原连接，不依赖旧场景账号密码
