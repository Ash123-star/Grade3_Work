# 实施批次与协作契约

- Issue：[#58](https://github.com/Ash123-star/Grade3_Work/issues/58)；Sprint：2026-11 月历交互；负责人 C。
- 分支：feature/58-calendar-task-drag；独立工作区来自 19db6f3，原目录的网络配置、详情及其他改动均保留。
- 用户授权整个实施批次后集中检查；本批允许 task/review 适配、V22 迁移、Flutter calendar、任务范围读取、最小安全命令存储、创建日期路由、相应测试和接口文档。测试代码随实现编写，完成本批再统一执行。
- 排除范围：人员/标签规则、审核层级/免审规则、D 的配色/溢出/节假日、通用日志/人员分页、其他工作区配置。

## 接入契约

D：继续使用一个纵向 PageController；拖动时停止用户滚动及分页吸附，controller.jumpTo 连续滚动。CalendarDayTarget 注册已加载月实际日期的 RenderBox 矩形；标题和相邻月空白格不是落点，未加载/错误页不注册。CalendarLoadedMonth 另注册已加载整页区域，只允许边缘滚动穿越页内空白/标题，不增加可落日期。CalendarTaskHandle 只提供事件交互，不改变条带 lane 和颜色。成员 ownerId 入参始终只读。跨周续段历史风险由本批对应回归用例确认，不能以旧文档为通过证据。

B：FormPage 新增 initialBusinessDate 和 scheduleConstraints；仅新建 dispatch 消费一次。具体时间必须确认；人员/标签/附件仍复用原表单。HTTP 只新增 If-Schedule-Constraints-Match 头，既有创建无头契约不变。

E：沿用当前 ReviewApplicationService 的配置审核链、禁止自审和审核事务；TASK_RESCHEDULE 增加 scheduleMode=MOVE、moveDays、startAt、deadline、scheduleConstraints。旧 deadline 候选兼容；不接入其他活动变更尚未交付的审核策略。

上述是代码接入契约，不代表已收到 B/D/E 的人工确认或部署批准。非作者审阅及正式部署状态必须另留证据。

## 日期与资源

上海时区的领域计算由 Java ZoneId 和 Flutter timezone 数据库各自实现，核验本地时刻及实际时长。新增 timezone 只用于排期计算，不替换日历组件。

单次范围最多 62 日/5000 条；完整读取最多 200 页、含一次整轮重读的总预算 45 秒，共享两个读取槽位。单次移动最多 15 秒等待、45 秒前台确认预算、最多两次追加同键确认。命令提交前复用 AES-GCM DraftStore 加密并读回；存储失败不发送。暂存只包括命令及结果 ID，不含会话凭据或整份任务。

## 验收和交付门槛

统一运行 Flutter 分析/测试/正式 HTTP APK、真实 PostgreSQL/Redis 后端 verify、OpenSpec strict。另记录设备端操作/独立审核/第二客户端链路、TalkBack/字体/设备 profile；未取得证据的条目保留未勾选。原自动交付门槛为全部功能验证通过后提交/推送/建 PR；用户于 2026-11-03 明确授权提前推送草稿 PR。合并、上线和归档仍依赖验收与审阅；未完成的设备验收或跨模块人工审阅不得写为已通过。

## 本批贡献与剩余门槛（2026-11-03）

真实 Android 拖动/独立审批/创建、Docker task/迁移和故障边界验证已完成；最终月末任务续段按本月实际日期裁剪，跨年两页均可长按拿起。修正审核 HTTP 多余字段与登出清理失败阻断，保留既有业务规则。共享模型/详情页的无关格式化已移除。

profile 10 次真实手势成功但慢帧比例未达标，TalkBack 与完整设备人工矩阵未完成；全仓仍有失败，B/D/E 人工确认及非作者审阅未取得。具体命令、退出码、截图、数据和风险统一维护在 verification.md，不将这些门槛标为完成。
