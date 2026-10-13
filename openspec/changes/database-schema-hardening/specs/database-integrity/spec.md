# Spec Delta

## Purpose

为企业协作系统提供可由 PostgreSQL 直接执行的跨租户、关系、审核和业务引用完整性，降低多人开发和后台任务直接写库造成数据损坏的风险。

## ADDED Requirements

### Requirement: Structured log task references

数据库 SHALL 以结构化关系保存日报关联任务，并拒绝跨公司或不存在的日报、任务关联。

#### Scenario: Valid same-company reference

- **WHEN** 写入同一公司的日报与任务关联
- **THEN** 关联成功且同一日报与任务组合不能重复

#### Scenario: Cross-company reference

- **WHEN** 使用另一公司的日报或任务写入关联
- **THEN** PostgreSQL 外键拒绝写入

### Requirement: Reporting cycle protection

数据库 SHALL 拒绝同一公司汇报关系形成直接或多级循环。

#### Scenario: Direct self relation

- **WHEN** 员工被设置为自己的直属上级
- **THEN** 写入失败

#### Scenario: Indirect cycle

- **WHEN** 新关系使 A、B、C 形成闭环
- **THEN** 写入失败且原有关系保持不变

### Requirement: Review self-approval protection

数据库 SHALL 保存审核申请人并拒绝为同一申请创建申请人自己的审核步骤。

#### Scenario: Applicant reviewer

- **WHEN** 审核步骤的 reviewer 与申请人相同
- **THEN** 写入失败

### Requirement: Versioned business constraints

关键状态、版本和 JSON 载荷 SHALL 具备数据库类型或检查约束，保证非法状态不能绕过服务层写入。

#### Scenario: Invalid task event

- **WHEN** 写入不支持的任务事件类型或非对象事件载荷
- **THEN** 写入失败
