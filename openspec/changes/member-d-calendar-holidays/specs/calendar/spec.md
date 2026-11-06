## ADDED Requirements
### Requirement: Monthly task previews
2026-11-05用户确认恢复五行折叠，替代2026-11-04完整行目标。系统 SHALL 每日期最多显示五个任务行；总数不超过五项时全部展示，超过五项时展示前四项与“+剩余数量”，剩余数为总数减四。点击剩余数量或日期 SHALL 打开当天完整授权清单，相邻月份也可点击。计数 MUST 按正式任务ID去重，不包含拖动候选或节假日，不能把预览上限变成查询上限。
#### Scenario: Six tasks
- WHEN 某日六条任务
- THEN 显示前四条和“+2”，点击后完整清单含六条
#### Scenario: Five tasks and ten tasks
- WHEN 某日分别有五条或十条任务
- THEN 五条全部显示，十条显示前四条和“+6”，刷新及跨周片段不重复计数
#### Scenario: No tasks or failed reads
- WHEN 日期无任务或请求失败
- THEN 无任务不显示虚假剩余数，请求失败提示重试而非伪造零条
#### Scenario: Adjacent month
- WHEN 点击相邻月份日期
- THEN 按真实年月日显示对应任务
#### Scenario: Fixed overflow badge and today marker
- WHEN 同月包含空闲日期、五条任务日期和超过五条任务日期，或剩余数量达到三位以上
- THEN 系统 SHALL 使用与任务数量无关的统一基础周高；剩余数量以黄色圆角胶囊固定在日期格右下角，单行且限制在格内，不遮挡前四条任务、不拉长单元格；今天的右上角 SHALL 显示小黄鸭角色，日期、节日及休/班标记预留独立空间，拖动候选不计入剩余数量
#### Scenario: Calendar visible behind dispatch button row
- WHEN 有派发权限的用户查看公司月历
- THEN 月历滚动区 SHALL 延伸到底部导航上方，不为派发浮钮保留整行不透明空白；浮钮权限及点击操作保持不变
### Requirement: Mainland holidays
系统 SHALL 在客户端离线计算1900–2100年的节日本日，仅在元旦、除夕、春节、清明节、劳动节、端午节、中秋节、国庆节当天显示名称，不加星标，不在连休或补班日重复标注；同日重合合并名称。节日 SHALL 独立展示、不可拖动，不占任务五行且不计入任务剩余数，长名称可查看完整内容。服务端既有放假公告接口 MUST 保持兼容，其行政放假安排不能冒充节日本日。
#### Scenario: National Day vacation
- WHEN 查看十月一日至七日
- THEN 只有十月一日显示国庆节且不带星标，其他日期仅在恰逢其他节日本日时显示该节日
#### Scenario: Online arrangement and offline fallback
- WHEN 联网取得经服务端校验的公告或断网但存在本地缓存
- THEN 分别以最新公告或缓存显示独立休/班标记，名称仍仅显示节日本日；缓存可跨应用重启，离线/缓存状态明确，公告名不覆盖本地历法名，缓存或网络失败不阻塞任务
#### Scenario: Offline lunar festivals
- WHEN 无网络、服务端不可用或首次无缓存打开月历
- THEN 农历春节、端午、中秋及清明按本地历法日期立即显示，除夕取春节前一日；网络失败不丢弃本地节日，不在每格显示假期待更新，无公告缓存不猜调休
#### Scenario: Adjacent year and leap month
- WHEN 网格包含相邻年份或某年有农历闰月
- THEN 按真实公历年月日显示，农历节日不在闰月重复，同日重合名称均保留
#### Scenario: Unsupported year
- WHEN 客户端年份小于1900或大于2100
- THEN 明确提示计算范围，不抛异常或伪造日期，任务月历仍可用；服务端原2007–2100和非法年份400契约不变
