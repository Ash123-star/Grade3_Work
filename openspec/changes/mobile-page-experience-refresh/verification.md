# 移动端验收记录

日期：2026-10-24（Asia/Shanghai）
范围：`mobile-page-experience-refresh` 的移动端代码、Mock、HTTP 适配与 OpenSpec；未修改服务端、数据库或 Web。

## 环境

- Windows 11；Flutter 3.38.7；Dart 3.10.7。
- Flutter 位于 `D:\flutter`，未加入 PATH。依赖解析访问 `github.com/flutter/goldens.git` 超时，因此以下 Flutter 检查使用 `--no-pub` 和本地已解析依赖。
- Android 模拟器 `emulator-5554` 可见，已有安装包 `cn.pandora.pandora_mobile`。本次未覆盖安装或清除模拟器数据，也未执行设备验收。

## 自动化结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `openspec.cmd validate --all --strict` | 通过，退出码 0 | 38 项通过，0 项失败；只证明 OpenSpec 结构校验通过 |
| `D:\flutter\bin\flutter.bat analyze --no-pub`（`mobile/`） | 通过，退出码 0 | `No issues found!` |
| `D:\flutter\bin\flutter.bat test --no-pub`（`mobile/`） | 失败，退出码 1 | 267 项通过、31 项失败、2 项跳过 |
| `D:\flutter\bin\flutter.bat build apk --release --no-pub --dart-define=USE_MOCK=true`（`mobile/`） | 通过，退出码 0 | `assembleRelease` 163.5 秒；产物 `mobile/build/app/outputs/flutter-apk/app-release.apk`，115.7 MB |

测试失败不是单一模块：输出中可确认 AI 工作台输入/发送状态、Demo UI 与路由、日志流程、月历续段、下属资料、任务表入口、日志 HTTP 契约和工作流断言均有失败。代表性用例包括：

- `ai_workbench_test.dart`：`sending keeps keyboard focus and input until acknowledged`、`failed send keeps input and idempotency key until acknowledged`。
- `demo_ui_test.dart`：日志日期选择、导航栏顺序、AI 草稿预填断言。
- `demo_workflow_test.dart`：撤回保留首次提交窗口、直接编辑日志流程。
- `calendar_agenda_test.dart`：`bounded month cells open all records and revoke stale sheet data`。
- `command_http_contract_test.dart`：日志编辑提交失败后的重试版本。
- `member_workspace_contract_test.dart`、`profile_dog_ui_test.dart`、`week5_ui_acceptance_test.dart`、`workflows_test.dart`：成员资料、任务表入口/字段和派发表单交互。

失败名称为代表项，不是完整 31 项清单；本次执行器保留的全量输出有截断。不得将其余用例推断为通过之外的产品验收结论。

## 月历续段证据

单跑 `calendar_agenda_test.dart` 退出码 1。断言在 `test/calendar_agenda_test.dart:310` 找不到 `month-span:tasks:t6:2026-10-12T00:00:00.000`。临时诊断确认 10 月 Mock 月查询结果包含 `t6`（`startAt=2026-10-16`、`deadline=2026-10-20`），但该任务没有出现在月格 widget tree。临时诊断代码已移除。数据读取之后的轨道分配/布局原因尚未查明；#2 不通过，且尚无证据确认下一周周一续段。

## 未验证与限制

- 未按 360/390/412dp 和 1.5 倍字号完成设备操作、键盘占屏、双轴表格、图表钻取、头像上传、弹卡及权限变化的手工验收。
- 未采集滚动帧时长/慢帧、TalkBack 或减少动画证据；APK 构建通过不能替代这些验收。
- 未连接真实服务端。日志首次提交三日/提交后 24 小时直接修改、资料联系方式与组织关系权限、统计历史聚合/同范围导出、下属日志月状态、任务派发历史及正式直属审核/创始人免审仍按契约缺口处理。
- APK 构建输出提示 CupertinoIcons 字体未找到、仅包含 MaterialIcons；需确认实际产品页面图标和字体显示。
- 当前工作区包含服务端代码、接口文档及其他移动端工作区改动。本次未提交、推送、创建 PR 或归档 change。

## 当前验收结论

移动端实现路径已接入，但 change 尚未通过验收。分析、Mock APK 构建和 OpenSpec strict 校验通过；全量 Flutter 测试失败，且设备/手工及正式服务端契约验收未完成。功能任务及 8.1–8.5 均保持未勾选。
