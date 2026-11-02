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

## 2026-10-29接口实现记录（无新增验收结果）

用户要求继续补齐全部六组P0接口与#17后再统一测试。本批已将任务卡/区间、日志范围/月份状态/24小时正文直改、资料权威列和版本化更新、真实统计/钻取/CSV及单级审核接入源码，并维护追加V22迁移、SpringDoc schema和移动端适配。MEMBERSHIP始终保留管理员确认；历史创始人候选只在本人明确继续后校验应用，迁移不执行候选。

补充源码核对修正：审核列表和详情统一保留当前仍有权限的已决历史；月状态和日志ID取自同次查询；递归上级授权拒绝循环链提供额外范围；统计明细分页结束映射为客户端null；LOG_UPDATED通知映射回日志详情。统计分母可信标记及现时组织/阶段口径已同步契约。

本轮未运行任何测试、分析、编译、构建、服务启动、数据库迁移或OpenSpec strict。上文历史通过/失败记录仅属于当时版本，不能外推本批正确性。实现与待验收清单见 `docs/mobile-p0-implementation-status.md`；`docs/openapi.json`保持旧快照，最终启动服务后再生成。任务不新增勾选，未提交、推送、创建PR或归档。

2026-10-29剩余接口范围确认：用户取消意见反馈，删除移动端相关接口、表单和界面入口，旧support/feedback深链返回帮助页；保留任务成果反馈、评论及AI分析评价。任务RETURNED、成果反馈附件及团队目录沿用现有状态/权限接通；AI新增SELF/AUTHORIZED范围并在后台、重试与来源分析保持，confirm-task必须携带作业version，行锁/来源重验/TASK_CREATE审核/幂等回执同事务，V23新增确认回执表。任务评论与日志回复复用已有实现，不新增已停用阅读登记的人员清单。详细源码接入及最终验收边界见 `docs/mobile-remaining-api-implementation-status.md`。本轮无测试、分析、编译、构建、迁移执行、服务启动或OpenSpec校验；历史结果不能外推，所有新功能任务保持未验证，未提交推送。
## 2026-10-29 数据库与统一验收更新（取代此前本批未执行验收的状态）

用户已授权最终编译测试，且明确无需同步其他实际开发数据库。独立本地 PostgreSQL 已执行 server Flyway V1–V23；升级、资料列、历史数据保留、确认回执约束及核心 HTTP 契约得到运行验证。V22/V23 满足当前实现的数据存储需要，无需新增重复字段。最终后端定向 41 项通过、移动端定向 35 项通过，后端打包、Flutter analyze、正式接口模式 Android APK、Web build 均退出 0；运行服务已重新导出 docs/openapi.json。

整体仍未验收通过：最终 Flutter 全量 281 通过、3 跳过、44 失败；后端此前全量 425 项中139失败、21错误，修复后只重跑受影响定向组，不能外推全量通过。另保留设备、部署镜像数据库版本、真实供应商及 OpenAPI 展示警告等待验证。具体命令、日志、缺陷修复和剩余动作以 `docs/database-contract-verification-2026-10-29.md` 为最新依据。HCJ 工作区混合改动未提交/推送。