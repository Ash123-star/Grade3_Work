# 剩余移动端接口实现状态

日期：2026-10-29；分支HCJ；关联OpenSpec `mobile-page-experience-refresh` tasks 9.1–9.5；本地Issue `docs/issues/mobile-page-experience-refresh.md`。状态：源码接入、未验证。

用户确认：取消意见反馈，并删除移动端相关接口和入口；AI范围筛选及原子确认版本保护一并实施。按用户安排，本轮没有运行测试、分析、编译、构建、服务启动、数据库迁移或OpenSpec校验；没有更改或新增测试断言，没有提交/推送混合工作区。

| 能力 | 当前实现与契约 | 边界 |
| --- | --- | --- |
| 任务退回 | 复用POST `/api/tasks/{id}/events`，`type=RETURNED,version,text`；前端移除拦截，事件显示退回补充 | 派发人/管理员，FEEDBACK→RECEIVED；详情可显示需补充；参与人按新版本重新反馈；原事件/审计/outbox保留 |
| 成果材料 | 同事件接口仅FEEDBACK可带attachments，单次最多5个、累计最多100个 | 现有TaskAttachments校验同公司、本人未绑定材料或同任务既有材料；非空且未过期；绑定、正文、事件、版本和通知同事务 |
| 评论及回复 | 现有GET/POST任务comments及日志comments真实实现予以复用；parentId由移动端parentCommentId映射 | 同对象父节点、读取/写入范围、不可改删；任务评论必填幂等键，重复409 DUPLICATE_COMMENT且不重复通知；日志POST无幂等保证，重复会追加 |
| 团队目录 | GET `/api/organization/teams`，返回数组id/name/department_id/version | 和组织树同范围；ACTIVE账号；不扩大目录或人员权限；无分页/版本/幂等键 |
| AI范围 | POST `/api/ai/jobs`新增scope SELF/AUTHORIZED，默认后者；Flutter提供选择并标记结果范围 | SELF日志只本人、任务只本人参与/派发、重点只本人；候选人筛选在LIMIT之前；input保存scope，worker/retry/来源分析沿用；每次模型调用前重验身份及来源 |
| AI确认 | POST `/api/ai/jobs/{id}/confirm-task`携带version/actionIndex/task和Idempotency-Key | 作业行锁、版本/来源/派发权限、TASK_CREATE审核及回执原子提交；旧版本零写入，同键同内容回执重放、异内容冲突；原行动来源重验；客户端按审核对象导航 |
| 意见反馈 | 用户取消；删除support表单、我的反馈列表按钮、帮助页入口及Mock资源支持 | 旧深链回帮助页；HTTP无feedback注册路径；Mock旧请求拒绝；保留任务成果反馈、评论和AI分析评价 |
| 阅读人员清单 | 不新增 | 阅读登记已由产品停用，保留历史数据与兼容接口，不重新恢复移动端入口 |
| 头像附件 | 复用资料实际递归上级权限读取当前头像 | 同公司当前有效关系，其他私人上传不因上级身份开放 |

范围选择控件和确认结果页仅复用现有主题组件，未引入新依赖或新模型调用入口；AI详情按作业实际scope显示本人范围。团队目录Mock使用去重团队数据，并按管理员/创始人全公司、部门老总本部门、其他角色本团队过滤，与服务端组织树规则对齐。旧logs/update别名也已接入content直改，重复withdraw分支与过时不可用文案已清理。

## 数据库和最终统一验收

新增 `server/.../V23__ai_confirmation_receipts.sql`，为AI作业增加确认回执外键所需唯一键及ai_task_confirmations表，保存命令规范化摘要、原行动来源ID、作业版本及原响应。回执不存模型密钥或附件正文。范围选择复用input JSONB，无需猜填老作业范围；老input缺scope时按AUTHORIZED兼容。V22、V23均未执行，实际数据库尚未更新。

最终集中补齐并运行：后端标准脚本、V21→V22→V23升级、AI确认和并发编辑/重放/来源失权的HTTP链路、任务退回→反馈→验收及材料下载、评论/回复越权及重复、团队范围、Flutter接口与导航/旧深链、范围后台/重试一致性、静态分析/构建、OpenSpec strict及真实运行时OpenAPI生成。安全和可靠性至少两项非功能取证，明确退出码/环境/结果后再勾选tasks；现有旧测试对“反馈不可用/退回拦截/无scope/确认无version”的断言需按确认需求更新，不削弱业务规则。

`docs/openapi.json`仍为旧运行时快照，未手写伪造；本文件不证明任何链路通过。P0详见 `docs/mobile-p0-implementation-status.md`；原17点UI/设备历史失败仍需最终验收，不因本批接口接入而关闭。

## 2026-10-29 数据库与统一验收更新（取代此前本批未执行验收的状态）

用户已授权最终编译测试，且明确无需同步其他实际开发数据库。独立本地 PostgreSQL 已执行 server Flyway V1–V23；升级、资料列、历史数据保留、确认回执约束及核心 HTTP 契约得到运行验证。V22/V23 满足当前实现的数据存储需要，无需新增重复字段。最终后端定向 41 项通过、移动端定向 35 项通过，后端打包、Flutter analyze、正式接口模式 Android APK、Web build 均退出 0；运行服务已重新导出 docs/openapi.json。

整体仍未验收通过：最终 Flutter 全量 281 通过、3 跳过、44 失败；后端此前全量 425 项中139失败、21错误，修复后只重跑受影响定向组，不能外推全量通过。另保留设备、部署镜像数据库版本、真实供应商及 OpenAPI 展示警告等待验证。具体命令、日志、缺陷修复和剩余动作以 `docs/database-contract-verification-2026-10-29.md` 为最新依据。HCJ 工作区混合改动未提交/推送。