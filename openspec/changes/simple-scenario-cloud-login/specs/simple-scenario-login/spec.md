## ADDED Requirements

### Requirement: Simple scenario credentials
P0：系统 SHALL 通过追加的可选Flyway迁移将固定21个场景成员改为文档列出的短账号，并使用部署传入的至少6字符、UTF-8至多72字节测试密码。正式账号密码策略 MUST 保持不变，业务关联与权限 MUST 保持不变。

#### Scenario: Existing or new scenario database
- **WHEN** 部署显式启用场景数据并执行V3
- **THEN** SHALL 更新同一批种子用户登录名及BCrypt密码、撤销其旧会话并记录无凭据的审计，重复启动不重复重置

#### Scenario: Conflicting account or incomplete seed
- **WHEN** 任一短账号被其他成员占用或种子用户缺失/不匹配
- **THEN** MUST 回滚整批修改，保留原账号和会话，不覆盖其他用户

### Requirement: Cloud mobile connection
P0：移动端 SHALL 默认访问http://39.96.84.51/api并使用真实接口，允许API_BASE_URL显式覆盖。Android发布包 MUST 仅为该指定IP放行HTTP。

#### Scenario: Default and local override
- **WHEN** 未配置地址或显式传入本地联调地址
- **THEN** SHALL 分别连接云端或指定地址，HTTP失败不得回退Mock成功

#### Scenario: Unreachable deployment
- **WHEN** 云端不可达或尚未迁移短账号
- **THEN** MUST 显示真实连接/认证错误，不声称云端已更新
