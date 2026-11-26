## Why
二期员工合同需归档、按人员授权并可靠提醒到期。优先级P0，负责人B，Sprint待关联，Issue待创建。用户已确认Web独立入口、显式授权、30/7/0天站内提醒。
## What Changes
- 员工职责与现有岗位关联；独立Web合同管理。
- 管理员授予人员READ/MANAGE权限，合同附件读取实时校验。
- 指定授权人员接收到期提醒，事务outbox去重。
- 非目标：绩效奖金、联网实名认证、客户业务模型和第三方推送。
## Capabilities
### New Capabilities
- `employee-contracts`: 员工合同档案、授权及到期提醒。
### Modified Capabilities
无。
## Impact
organization、人事Web入口、附件授权及清理、通知outbox；新增前向迁移，不修改历史迁移。客户敏感字段依赖C/E接口，默认拒绝，不宣称已完成CRM联调。
