## Why
用户要求删除重复页名，将日视图改为列表、周视图一次展示整周、月历展示有限彩色记录。现有时轴需要横向滚动，与本次要求不符。

## What Changes
- 共享页面骨架删除顶部页名，无操作和返回需求时删除整条工具栏；其余操作随页面内容滚动。
- 日视图展示全部任务和日志列表；周视图七列摘要无内部滚动；月历每格两条简写及溢出数量。
- 日期可打开当天完整列表，记录复用既有详情和权限控制下的编辑入口。

## Capabilities
### New Capabilities
- `flutter-calendar-agenda`: 无重复页名、日列表、整周概览与月历记录。
### Modified Capabilities

## Impact
仅 Flutter 页面、测试和设计文档。Repository、后端接口、数据库、导航与权限不变。关联本地 Issue `docs/issues/flutter-calendar-agenda.md`。

最新视觉要求：周视图纵向七行，记录胶囊宽度 156dp，不铺满页面；月历无表格直线边框，圆角日期格与留白，保留两条预览、+N 和当天详情。顶部操作随内容滚动。
