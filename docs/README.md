# 仓库文档总索引

产品从 [方案](../方案.md) 开始，协作以 [AGENTS核心规则](../AGENTS.md) 和 [开发流程](development-workflow.md) 为准。**先找主题、原位更新；只有必要才新建文档，只有具体大功能才新建OpenSpec。** 一个主题一个维护入口；单次交付写Issue/PR，过程日志/截图放忽略的`output/`。目录职责、更新和删除流程见 [管理框架](development-workflow.md#文档管理框架核心)。

## 需求、协作与规格

| 内容 | 入口与定位 |
| --- | --- |
| 产品与课程依据 | [产品基线](../方案.md)、[实训要求](<2026-2027-1 软件开发与测试综合实训 项目要求.md>)、[原始PRD](Pandora_PRD.docx)；PRD为原始输入，取舍以确认后的产品基线/规格为准 |
| 核心规则及协作 | [AGENTS](../AGENTS.md)、[开发流程与Git比较](development-workflow.md)、[PR模板](../.github/pull_request_template.md) |
| 分工与候选范围 | [MVP分工](mvp-team-division.md)、[OpenSpec指南](openspec-guide.md)、[活动变更](../openspec/changes/)、[同步规格](../openspec/specs/) |
| 客户端入口 | [Flutter运行](../mobile/README.md)、[移动端专题索引](../mobile/docs/README.md) |
| 脚本 | [脚本索引](../scripts/README.md)；运行参数以脚本为准 |

## 运行、架构与数据

| 主题 | 唯一入口及补充材料 |
| --- | --- |
| 后端启动与架构 | [运行配置](backend.md)、[模块边界](backend-architecture.md)、[远端连接](remote-backend-connection.md) |
| 接口 | [后端契约](backend-interface.md)、[OpenAPI快照](openapi.json)、[客户端接入与待验收](backend-interface-gaps.md)；Controller/运行时SpringDoc为核对来源 |
| 数据库 | [server Flyway结构](database-schema.md)；[独立数据设施](data-infrastructure.md)不得混入业务迁移 |
| 初始化与场景 | [年度场景重建](annual-scenario-rebuild.md)、[本地种子](local-scenario-data.md)；不可当真实业务数据 |
| 云端运维 | [systemd部署/备份/回滚](cloud-systemd-deployment.md)；旧Compose环境须明确隔离 |
| 认证/组织/审核 | [认证](member-b-auth.md)、[组织](member-b-organization.md)、[审核](member-b-review.md)；后续权限增量以当前契约与对应规格为准 |
| 个人事项 | [接口与权限](personal-todos-interface.md)、[客户端设计](../mobile/docs/home-daily-todos-direction.md) |
| 任务与月历发布 | [任务生命周期](task-lifecycle-release.md)、[月历移动/完整行/证据/回滚](calendar-task-drag-release.md)；不再分散维护批次发布文件 |

## AI专题

| 主题 | 入口 |
| --- | --- |
| 办事工作台 | [API](ai-work-assistant-api.md)、[部署/迁移/专项验收](ai-work-assistant-deployment.md)、[需求和未完成项](../openspec/changes/ai-work-assistant/tasks.md) |
| 地图与长期记忆 | [长期方案](../AI地图长期记忆技术方案.md)、[运维](ai-map-operations.md)、[验证](ai-map-validation.md)；方案不等于已交付 |
| 检索实验 | [检索评估](ai-map-retrieval-evaluation.md)、[指标数据](ai-map-retrieval-metrics.json) |
| 四路线实验 | [对照评估](ai-map-four-way-evaluation.md)、[评估数据](ai-map-four-way-evaluation.json)；与检索实验不是同一基准 |

## 验证与历史材料

最新仓库已记录的完整自动化结果见 [统一验证入口](backend-validation.md)：2026-11-05后端511项（0失败/0错误/1跳过）、Flutter HTTP50/Mock373通过（5项opt-in跳过），分析/Web构建/strict退出0。日期、提交、命令和环境以该文件为准；真实供应商、设备性能、TalkBack及完整人工矩阵仍有未验收项。本次文档清理未重跑业务测试，也未部署服务。

以下保留独立验收价值，**只适用于所记录提交和环境**，不可当作最新失败数或对当前环境的健康承诺：

| 历史主题 | 材料 |
| --- | --- |
| 2026-10-29/30接口整合 | [数据库契约验证](database-contract-verification-2026-10-29.md)、[合并前验证](premerge-verification-2026-10-29.md)、[前后端联调](frontend-backend-integration-validation-2026-10-30.md) |
| 权限、安全、管理端 | [安全回归](member-b-security-regression.md)、[week6真实联调](member-b-week6-live-validation.md)、[管理端验收](web-admin-management-validation.md)、[week7验收](zhw-week7-validation.md) |
| 月历、课程阶段材料 | [D月历范围](member-d-calendar.md)、[课程周报2026-10-23](weekly-report-2026-10-23.md) |
| 客户端限定批次 | [移动端历史与设备限制](../mobile/docs/README.md#历史验收与限制) |
| 移动端补充快照 | [历史补充YAML](mobile-openapi-contract.yaml)；不是运行时能力，不据此猜接口 |

其他重复状态表、本地Issue副本、过期handoff与批次报告已合并到以上主题；需要旧原文时从Git历史查询。活动OpenSpec的未完成项和必要机器证据保留，不能为减少目录而伪造完成或归档。素材许可证与署名随各素材目录维护，不属于清理对象。
