# 2026-10-23 验证记录

## 已接入

- mobile/lib/shared/widgets.dart PageFrame：返回按钮48×48dp，与柴犬装饰及Expanded标题同行、垂直居中；长标题单行省略。仅存在操作时显示下方Wrap，不再生成第二行返回区域。
- 保留showTitle=false、Navigator.canPop、原BackButton返回语义、随正文滚动及现有背景。月历与手势的已有混合改动保留。
- 排查mobile/lib中的PageFrame、BackButton、AppBar、箭头和Scaffold；日志/任务详情及其加载/失败页、列表、表单、设置、下属工作台、人员、审批、AI工具等使用共享PageFrame，因此统一应用修复。未发现第二套独立页面返回栏；弹窗关闭与日期切换不属于此问题。

## 已验证

1. 实施前仓库根目录 `openspec.cmd validate --all --strict`：退出码0，32 passed / 0 failed。
2. mobile目录 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/shared/widgets.dart lib/features/common/detail_pages.dart lib/features/common/form_page.dart lib/features/settings/utility_pages.dart lib/features/dashboard/member_workspace.dart`：退出码0，No issues found。
3. 仓库根目录 `git diff --check`：退出码0。

## 未验证

遵照此前仅授权定向静态检查的范围，未执行测试、构建、模拟器或设备验收。各页视觉对齐、长标题/字体放大、操作区滚动、返回链路及无障碍点击范围仍缺运行态证据，任务2.1保持未勾选。现有calendar_agenda_test中的历史断言仍假设默认隐藏二级标题，与当前代码默认showTitle=true不一致，本批未修改或执行这些已有测试，不能据此宣称测试通过。

工作区HCJ含前序混合改动；未提交、推送或创建PR，未触碰.diagnostics。远程Issue尚未创建。

## 顶行水平定位与灰字修订

- PageFrame顶行左右各预留86dp，中间标题TextAlign.center，标题中心与完整栏宽中心重合；返回在左侧48×48dp区域，柴犬装饰保留。showTitle=false与原操作区规则保留。
- form_page.dart删除状态文字actions/Center，将草稿、24小时内可修改、已锁定前缀与原保存信息合并为同一个Text.rich，TextAlign.start；无新增独立提示行，窄屏可自然换行。只修改显示，24小时窗口规则不变。
- 实施前strict退出码0，32 passed / 0 failed；格式化退出码0。mobile目录执行 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/shared/widgets.dart lib/features/common/form_page.dart lib/features/common/detail_pages.dart`，最终退出码0、No issues found。检查等待较久，确认进程后读取原会话结果，未重复启动。
- `git diff --check`退出码0。未运行测试、构建、设备或模拟器，居中、窄屏/大字号、提示组合与返回链路仍未运行验收；任务3.1保留未勾选。

## 返回与头像标题组追加修订

- 最新布局替代前述86dp方案：返回按钮独占左侧48×48dp区域，中央为30dp头像、6dp间距、Flexible单行标题的紧凑组；右侧48dp对称预留，确保整组相对栏宽居中，长标题省略。
- 头部无外层水平padding；PageBody将16dp水平留白从ListView移到各正文child，头部不被叠加缩进，原正文宽度保持。独立操作区仍保留16dp边距。日志灰字维持合并保存信息靠左显示。
- 实施前strict 32 passed / 0 failed，退出码0。格式化退出码0。
- mobile目录 `D:/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/shared/widgets.dart lib/features/common/detail_pages.dart lib/features/common/form_page.dart lib/features/settings/utility_pages.dart lib/features/dashboard/member_workspace.dart`：No issues found，退出码0。
- `git diff --check`退出码0。未执行测试、构建或设备，标题组视觉居中、边缘点击、正文滚动及大字号尚未运行验收，任务4.1不勾选。无提交、推送或PR，保留其他混合改动。
