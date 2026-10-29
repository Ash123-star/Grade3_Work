# Secure Local State Specification

## Purpose

Protect private employee drafts and recoverable sessions on the native client while preserving account, business-date and revision isolation, requiring fresh server identity validation before any recovered business access.

## ADDED Requirements

### Requirement: Encrypted account-scoped drafts

The client SHALL store diary draft content in an account-and-business-date scoped Drift record whose content is authenticated encrypted before persistence.

#### Scenario: Save and restore a draft

- **WHEN** an authenticated user saves a draft for a business date
- **THEN** the database stores ciphertext and nonce with an opaque lookup, and reopening that account/date restores the same fields and confirmed server draft version without exposing them in the database

#### Scenario: Account isolation

- **WHEN** the active account changes
- **THEN** a read for the new account MUST NOT return the previous account's draft, even when the business date is identical

#### Scenario: Revised or different-server draft

- **WHEN** a draft is read under a different server or revision baseline
- **THEN** it MUST NOT be restored into the current editor or submitted with a stale server version

#### Scenario: Corrupt local data

- **WHEN** ciphertext authentication fails or the key is unavailable
- **THEN** the editor retains current input, shows a recoverable storage error, and MUST NOT report the draft as saved

### Requirement: Protected session recovery

The client SHALL keep recoverable session material only in platform secure storage and SHALL validate it through the existing authenticated identity endpoint before granting business access.

#### Scenario: Valid restart

- **WHEN** secure material exists and `auth/me` returns the same active account
- **THEN** the client restores the session and opens the default 导图 route

#### Scenario: Invalid or changed identity

- **WHEN** the material is expired, missing required fields, rejected, or maps to a different account
- **THEN** the client deletes the material and remains on the login or safe pending route without issuing business reads

#### Scenario: Network recovery failure

- **WHEN** identity validation times out
- **THEN** the client retains secure material for explicit retry and shows a safe recovery screen with no business content

#### Scenario: Superseded account request

- **WHEN** a recovery or revocation response arrives after the account changed
- **THEN** it MUST NOT replace or revoke the successor's session or stored credential

#### Scenario: Logout

- **WHEN** the user logs out successfully or the server rejects the session
- **THEN** the client removes the current account's secure material and does not claim that a new session exists

### Requirement: Legacy migration

The client SHALL migrate existing draft preferences only for the current account/date and SHALL delete the legacy keys after a successful encrypted write.

#### Scenario: Migration failure

- **WHEN** the legacy value cannot be encrypted or written
- **THEN** the client keeps the editor input and legacy value for retry and reports a storage failure

### Requirement: Confirmed default credential retention

P0：原生移动端登录成功后 SHALL 默认保存受保护的最小认证记录，不保存账号密码。安全写入 SHALL 回读确认，服务端有效期和撤销权限 MUST 保持权威。

#### Scenario: Login followed by application state recreation

- **WHEN** 用户通过当前登录接口登录，随后销毁应用状态并重新打开同一服务地址的应用
- **THEN** 客户端 SHALL 用保留的 token 调用 auth/me，在同一有效身份确认后进入默认导图，无需再次输入或提交账号密码

#### Scenario: Unconfirmed secure write

- **WHEN** 安全存储写入抛错或回读内容不一致
- **THEN** 客户端 MUST 显示仅本次运行有效的保存失败提示，不声称下次可免密恢复，也不得降级保存明文密码

#### Scenario: One week session lifetime

- **WHEN** 用户在无 SESSION_HOURS 显式覆盖的环境登录
- **THEN** 服务端 SHALL 签发自登录起168小时有效的会话并返回准确 expiresAt，移动端 MUST 保存此值；主动退出、改密、停用和过期仍使会话失效，已有记录不得自动延期
