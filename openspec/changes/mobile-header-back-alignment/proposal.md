## Why

共用PageFrame将标题与返回按钮分两行，日志和任务详情等二级页出现错行。

## What Changes

- 返回按钮固定在顶行安全区域最左侧；柴犬头像与标题紧邻6dp组成一组，整体相对整栏水平居中，与返回操作区分离。
- 日志编辑状态灰字与已有保存信息合并靠左显示，移除独占顶部操作行的Center布局。
- 共用该布局的详情、表单、设置、列表及成员页面统一修正；操作区继续换行，主导航隐藏标题规则保留。

## Capabilities

### New Capabilities
- `mobile-header-alignment`: 二级页返回按钮与标题同行。

### Modified Capabilities
- None.

## Impact

只调整Flutter共享PageFrame，无接口、权限、数据、依赖或路由变化。P1，本地Issue为docs/issues/mobile-header-back-alignment.md，远程编号未创建。
