# Design

当前接口GET /api/task-labels按公司、部门和ACTIVE状态筛选，返回id/name/color/status；任务读取返回label投影。沿用recordsProvider('task-labels')比表单自行新建HTTP客户端更简单，也能复用认证、权限、错误及账号切换失效机制。

选择器只把合法活动记录构造成选项，以Record.id提交，经已有Repository映射为labelId。名称和颜色来自同一记录，不做ID到固定名称/颜色的转换。后台已停用/不可见的历史标签在编辑时显示原名称并要求重新选择，不能悄悄替换。异步数据到达后使用controller当前值校验，避免回显时竞态。加载/错误/空列表不得回退Mock；刷新后选中项不存在则阻止提交。

MockRepository增加同一task-labels资源，从演示任务元数据汇总标签，真实模式不使用该路径。维护侧对话专属文件与规划目录，不改主线程数据库文件。验收为定向HTTP适配器+组件测试、Dart分析与格式化，覆盖动态ID/颜色、实际提交、失败重试、空与失效标签。
