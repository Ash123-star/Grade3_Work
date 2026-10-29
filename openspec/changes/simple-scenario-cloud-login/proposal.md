# Proposal

## Why
用户要求简化既有21个虚构场景账号与测试密码，并将移动端连接到云端39.96.84.51。健康检查确认80端口/api可达。

## What Changes
- 新增可选场景V3迁移，将登录名改为短名并使用部署传入的测试密码，撤销这些账号的旧会话。
- 场景初始化允许至少6字符密码，正式注册与改密策略不变。
- 移动端默认连接http://39.96.84.51/api，保留API_BASE_URL覆盖，Android仅为该IP允许HTTP。
- 更新账号表、部署步骤与验收工具。

## Capabilities
### New Capabilities
- `simple-scenario-login`: 场景短账号和云端连接。

## Impact
涉及可选种子迁移、初始化校验、Flutter地址配置及Android网络策略；正式迁移与用户业务ID不变。云端执行需部署新版本且显式启用场景迁移。

关联Issue：#42。用户明确要求跳过本轮运行验收并直接通过PR合并main。
