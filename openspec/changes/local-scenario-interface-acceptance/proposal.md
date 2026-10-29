# Proposal

## Why

用户要求在本地真实启动后端和移动端，插入足够且相互关联的可信演示数据，并验证接口。现有 acceptance 库混有随机自动测试夹具，不适合作为可理解的联调场景。

## What Changes

- 提供默认禁用、显式启用的独立 Flyway 数据目录，写入后端配置指定的数据库，使用当前 V1–V23 表结构。
- 一次性追加虚构企业与人员、部门/团队/真实直属关系、任务生命周期、日志和评论、审批与通知；不覆盖现有数据，不硬编码密码。
- Flyway 初始化相关联的历史场景，当前 HTTP API 验证业务链路；明确区分初始化历史与真实接口请求。
- 启动真实后端和 Android 模拟器，验证角色范围、异常请求、附件和一周会话恢复。

## Capabilities

### New Capabilities
- `local-demo-runtime`: 本地场景数据与接口验收工具。

### Modified Capabilities
无；不新增业务接口或修改业务规则。

## Impact

新增 scripts 工具、演示数据说明与验证报告；数据/凭据/截图/日志仅在 Git 忽略的 output 下。依赖现有 WSL PostgreSQL/Redis 和 Android SDK。

2026-10-29后续调整：用户授权简化测试凭据，见#42与simple-scenario-cloud-login，追加V3，公开测试密码仅供虚构场景使用。
