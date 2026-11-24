## ADDED Requirements

### Requirement: 统一客户主数据
系统 SHALL 为公司内个人和企业客户分配稳定客户 ID，并保存名称、联系方式、类型、状态和可选商城外部 ID。商城外部 ID 在同一公司内 MUST 唯一且可空；重复时必须拒绝而不是自动合并。客户读取和写入 SHALL 同时限制当前公司和当前 ACTIVE ADMIN。

#### Scenario: 创建个人和企业客户
- **WHEN** ADMIN 提交合法的个人或企业客户名称和类型
- **THEN** 系统 SHALL 返回新的 `cus_` 客户 ID，初始状态 ACTIVE、版本 1

#### Scenario: 外部 ID 冲突或跨公司访问
- **WHEN** 两个客户使用同一商城外部 ID，或请求读取其他公司的客户
- **THEN** 写入 SHALL 返回 409 且不产生部分记录，跨公司读取 SHALL 返回 404

### Requirement: 商城会员与服务进度
系统 SHALL 支持为一个客户绑定公司内唯一的商城会员 ID、等级、加入/到期日期和状态。客户详情 SHALL 同时返回会员、权益和服务进度；服务人员 SHALL 能追加带阶段和说明的进度记录，并按时间回查。

#### Scenario: 绑定或更新商城会员
- **WHEN** ADMIN 首次绑定会员使用 version=0，或更新时提交当前 version
- **THEN** 系统 SHALL 保存会员信息；版本不符 SHALL 返回 409，会员 ID 冲突 SHALL 返回 409

#### Scenario: 追加会员服务进度
- **WHEN** ADMIN 为客户提交非空阶段和可选说明
- **THEN** 系统 SHALL 追加一条进度记录，详情和进度列表可回查

### Requirement: 权益有效期与次数
系统 SHALL 为年卡/商城权益保存类型、名称、开始日期、结束日期和可选次数上限。结束日期 MUST 不早于开始日期；次数上限 MUST 为正整数或空。客户详情和权益列表 SHALL 返回权益有效期、状态和已用次数所需信息；权益核销历史 SHALL 可按客户和权益回查。

#### Scenario: 发放年卡权益
- **WHEN** ADMIN 提交合法的 ANNUAL_CARD 及有效期
- **THEN** 系统 SHALL 创建 ACTIVE 权益并返回其 ID 和版本

#### Scenario: 非法有效期或次数
- **WHEN** 结束日期早于开始日期，或次数上限为 0/负数
- **THEN** 系统 MUST 返回 400 且不创建权益

### Requirement: 幂等的权益核销
权益核销 MUST 携带 `Idempotency-Key`。系统 SHALL 以 `(company, benefit, key)` 唯一记录核销；同一键重复提交 SHALL 返回第一次结果，不得重复扣次。权益停用、当前上海日期不在有效期内或已达次数上限时 MUST 拒绝新的核销。

#### Scenario: 重复提交同一核销
- **WHEN** 同一权益使用相同 Idempotency-Key 再次提交
- **THEN** 系统 SHALL 返回原核销记录和相同 used/remaining，不新增扣次

#### Scenario: 失效或超次核销
- **WHEN** 权益已停用、已过期或可用次数已用完
- **THEN** 系统 MUST 返回 409，且数据库 SHALL 不新增核销记录

#### Scenario: 跨客户或跨公司核销
- **WHEN** 请求的客户与权益不匹配，或权益属于其他公司
- **THEN** 系统 MUST 返回 404，且不得返回其他客户的权益或核销信息
