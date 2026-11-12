## ADDED Requirements

### Requirement: Personal task pinning
Could：有效用户 SHALL 能对本人可见的任务进行个人置顶与取消置顶；置顶只影响本人的任务管理列表，MUST NOT 触发审核、修改任务版本或对他人可见。每人最多置顶 10 项。

#### Scenario: Pin a task
- **WHEN** 用户对可见任务调用置顶接口
- **THEN** 任务 SHALL 在本人 `GET /api/tasks` 结果中以 `pinned=true` 排在未置顶任务之前，多个置顶按置顶时间倒序，任务 version 不变

#### Scenario: Pin limit
- **WHEN** 用户已置顶 10 项后再置顶第 11 项
- **THEN** 服务端 MUST 返回 409 `PIN_LIMIT`，已有置顶不变，客户端提示“最多置顶 10 项”

#### Scenario: Pin invisible task
- **WHEN** 用户对不在数据范围内或其他公司的任务调用置顶
- **THEN** 服务端 MUST 拒绝并不写入记录

#### Scenario: Idempotent toggle
- **WHEN** 重复置顶已置顶任务或取消未置顶任务
- **THEN** 服务端 SHALL 返回成功且不改变原置顶时间

#### Scenario: Pins are personal
- **WHEN** 用户 A 置顶任务后，同样可见该任务的用户 B 查看列表
- **THEN** 用户 B 的列表 MUST NOT 显示为置顶或改变排序

### Requirement: Tenure display in profile
“我的”、个人资料页及人员目录点击员工后的详情 SHALL 根据服务端 `employmentStartDate` 按上海业务日期显示完整的“X年X个月X天”工龄，月周年日遇短月截到月末，余天从该周年日起计算；入职日期为空或晚于今天时 MUST 显示“未提供”，不得从注册时间推测。

#### Scenario: Known start date
- **WHEN** 入职日期为 2025-08-01，今天为 2026-11-01
- **THEN** 页面 SHALL 显示“工龄 1年3个月0天”及入职日期

#### Scenario: Short tenure
- **WHEN** 入职不足一个月
- **THEN** 页面 SHALL 显示“0年0个月X天”，X 为实际经过天数

#### Scenario: Missing start date
- **WHEN** 资料中 `employmentStartDate` 为 null
- **THEN** 页面 SHALL 显示“未提供”

#### Scenario: View an authorized employee
- **WHEN** 用户点击服务端授权目录中的员工
- **THEN** 详情 SHALL 展示该员工的真实入职日期和工龄，MUST NOT 跳转为当前登录人的资料或扩大查询权限
