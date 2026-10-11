## 1. 配置与说明

- [x] 1.1 盘点现有配置、目录、技能及版本，安装 CLI 1.14.1
- [x] 1.2 使用用户指定 lyb 分支，补齐共享上下文、分工和 artifact rules
- [x] 1.3 补充使用文档，修正既有 Purpose 占位说明，保持产品需求不变

## 2. 验证与追溯

- [x] 2.1 运行完整严格校验及四种 artifact instructions 加载检查，记录结果
- [ ] 2.2 关联维护 Issue/Sprint，检查差异并提交、推送和创建 PR，由非作者审阅

首次严格校验：8 passed / 1 failed；ai-map-direction-ui 的 Purpose 占位警告导致严格失败。未运行后端业务测试，此次仅配置和文档维护。

最终验证（2026-10-11，lyb）：CLI --version 为 1.14.1；validate --all --strict 为 10 passed / 0 failed；proposal instructions 返回 spec-driven 和包含 B 职责的 context，规则数为 3；specs/design/tasks 规则分别为 4/3/3；git diff --check 通过。

CLI 在当前进程 PATH 中尚未被 Get-Command openspec.cmd 找到，已通过 E:/Dev/npm-global/openspec.cmd 绝对路径实际运行。未修改用户系统 PATH，文档提供定位与临时 PATH 方法。

2.2 未完成：本次配置维护随成员 B 开发准备记录，关联认证 Issue #3；Sprint 待关联。配置和说明整理为本地提交。用户要求暂不推送 GitHub，因此远程 PR、非作者审阅及归档仍未完成。
