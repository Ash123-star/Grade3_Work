# 成员 B 第二批：组织维护与范围

Issue #4；OpenSpec member-b-backend-readiness 3.1–3.5；依据 MVP 分工，实际验证见 member-b-delivery.md。

## 实现与兼容性

调用路径：OrganizationController → OrganizationApplicationService → OrganizationPolicy / OrganizationValidation / OrganizationRepository。
Controller 不包含 SQL；应用服务负责组织用例、权限、事务和审核申请；repository 在 SQL 中过滤公司、部门、团队与人员范围。
五角色沿用现有主规格：ADMIN/FOUNDER 可读当前公司；DIRECTOR 可读自己与同部门；LEADER 可读自己与同团队；EMPLOYEE 仅本人。组织树部门/团队同样在 SQL 过滤。部门 id/name 目录仍为当前公司的非人员目录，未改为个人部门；注册部门仍是独立公开入口。

GET /api/organization 保留 departments、teams、users，其中 users 仍是 items/total/nextCursor 对象，修复默认 100 人截断，返回完整授权树；不会包含范围外或停用人员。
GET /api/organization/people 保留 search/dispatch/cursor/limit，页大小 1–100；dispatch=true 要求派发资格，只返回 ACTIVE；普通查询保留原有非 DISABLED 范围。nextCursor 按实际返回条目推进，末页不跳过剩余内容。
超大组织树可能需要未来独立分页契约，当前 MVP 保留完整树以兼容客户端形状；性能需单独验证。

## 组织写入与审核

- membership-application：仅 PENDING，departmentId/version/reason；存在待审申请409；部门无效404；独立管理员确认后激活。
- reviewer-application：ACTIVE 且尚无复核职责，version/reason；独立管理员批准，仅变更复核职责，不改变员工角色。
- users/{id}/revisions：ADMIN；version/reason，允许 name、departmentId、teamId、role、status、dispatchEnabled、companyReviewer、managerId；禁止任意其他字段。
- departments/revisions、teams/revisions：ADMIN；新建 version=0，更新带 id 与已有 version；name 必填，team 需 departmentId。
- review-policy 与 review-policy/revisions：ADMIN；允许调整团队/部门任务复核布尔字段，公司独立复核不能关闭。
- audit：ADMIN，cursor/limit，分页审计记录。

错误：非法字段/角色/关系400，权限不足403，范围外或不存在实体404，版本冲突及重复归属申请409。申请创建不使用幂等键；现有多候选最终以版本检查解决竞争，不添加参考 PRD 单条待审限制。
关键修改候选生成后旧值持续生效，所有审核通过才更新；禁止申请人自审，驳回须原因。

## 完整性与事务

组织候选创建及最终审核应用复用 OrganizationValidation，先锁公司再检查关系；同公司部门、团队所属部门、五角色、ACTIVE/DISABLED 状态、管理角色组织配置、布尔权限、有效汇报上级、无汇报环、最后有效管理员都需成立。
公司锁使并发停用/降级不能分别验证后消灭全部管理员。审核应用已有版本条件更新；历史任务与日报保持不删除。当前审核仍通过兼容静态入口调用该验证器，第三批再处理跨模块应用边界。
本批无数据库表结构变更，V1–V5 不重写；JavaDoc 随入口更新，E 的汇总契约及真实客户端核对待完成。

## 验证

OrganizationPolicyTest 覆盖无效角色/状态/权限、角色组织要求、汇报环和管理员边界。
OrganizationIntegrationTest 使用独立公司和真实 HTTP/PostgreSQL，覆盖五角色与跨公司、跨部门、跨团队；113 人树与分页；无效关系候选不落库；审核前后数据及旧会话范围；驳回；待确认/分页拒绝；并发最后管理员保护。
公共 BackendIntegrationTest 保持原样，不能将定向通过报告为全套通过。
