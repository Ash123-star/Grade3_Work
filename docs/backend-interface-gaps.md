# 客户端接口接入与待验收

本文件集中记录接入边界，不复制正式DTO/错误清单；协议以 [后端接口](backend-interface.md)、[运行时快照](openapi.json) 及Controller为准，页面映射见 [客户端矩阵](../mobile/docs/api-surface-coverage.md)。原P0、剩余接口、handoff和旧缺口登记已合并，不能按旧批次的“未实现/未迁移”状态重复开发。

## 接入范围

| 主题 | 已接入契约与边界 | 仍需关注的验收 |
| --- | --- | --- |
| 任务读取 | received-card含真实派发时间/稳定分页；from/to左闭右开区间相交；participantId/ownerId兼容并拒绝冲突 | 终态历史、缺时间、跨月/跨公司、分页与真实日期过滤 |
| 日志与月份 | 下属按部门/日期/关键词/owner过滤且不含他人草稿；上海自然月SUBMITTED/MISSING/FUTURE/UNKNOWN与可信入职日 | 未知入职日不造假，失权/离职历史范围及月状态与logIds一致 |
| 日志正文 | PUT /logs/{id}/content：作者首次提交后24h、version、历史/审计/outbox；首次提交限今天/昨天/前天，首次时间不重置 | 三日与24h独立边界，管理员无作者例外，旧修订/撤回不能绕过 |
| 资料与头像 | phone/email/gender/age权威列，字段缺席保留、选填null清空；本人写，读取按真实组织范围；头像受控附件 | 旧JSON非法值保留、版本冲突、电话冲突、私人上传不得扩权 |
| 统计与导出 | summary/details/export共享授权查询和事实源；真实事件、零/未知分母返回null；BOM CSV上限10000且防公式注入 | 当前组织/阶段与历史快照不能混称；不同指标不能强行与CSV总量比较 |
| 审核 | expectedVersion、自审拒绝、驳回理由、当前关系重验、reroute保留历史 | 无有效人保持PENDING；MEMBERSHIP管理员确认；创始人互审等后续增量以现行审核契约为准 |
| 退回与成果 | RETURNED走任务events，FEEDBACK阶段由派发者/管理员退回RECEIVED；FEEDBACK支持受控附件 | 退回→补充→验收、非法阶段、旧版本与附件绑定原子性 |
| 评论与团队 | 同对象parentId，任务评论幂等键/重复409；日志回复无幂等保证；teams沿用组织范围 | 错父节点、越权、重复通知；写评论不自动盲重试 |
| AI范围及确认 | SELF/AUTHORIZED随worker/retry/来源分析保持；confirm-task携带version/actionIndex/task/幂等键，行锁、来源重验、TASK_CREATE和回执同事务 | 失权、并发编辑、旧版本零写入、同键异内容冲突与审核导航 |
| 已取消能力 | 意见反馈入口/表单/Mock移除，旧深链转帮助；日志阅读登记停用，不新增阅读人员清单 | 不根据历史草案恢复；保留任务成果反馈、评论与AI分析评价 |

资料/日志/审核V22及AI确认V23已经发布并有升级验证，不能再写成“未跟踪/未执行”。后续V27–V30等以server Flyway及当前部署记录为准，不修改已发布迁移，不混用deploy/postgresql。

## 验证状态与后续维护

最新仓库已记录的完整验证为 [2026-11-05整合结果](backend-validation.md)：后端511项（0失败/0错误/1跳过），Flutter HTTP50与Mock373通过（5项opt-in跳过），分析/Web构建/严格校验退出0。其环境与提交见该文；本次文档整理未重跑业务测试。10月29/30日的失败清单属于历史，不能作为当前失败数。

自动测试不代表逐页面Android、实际供应商或生产环境全部通过。真实DeepSeek/OCR、TalkBack、目标设备性能及完整人工矩阵仍未补验，相关OpenSpec未完成任务继续保留。接口存在也不等于文件选择/保存、跨端恢复或每个权限场景已在设备验收。

新增问题直接在对应远端Issue/已有大功能tasks记录触发条件、期望/实际、优先级、代码基线和复现证据；小修复不为每条缺口新建OpenSpec。公共契约变更先分析影响并同步Controller、SpringDoc、OpenAPI和调用方，不能猜路径。
