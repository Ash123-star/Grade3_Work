# Claude Code 仓库入口

@AGENTS.md

所有核心规则以 [AGENTS.md](AGENTS.md) 为准，执行步骤见 [开发流程](docs/development-workflow.md)，产品基线见 [方案](方案.md)，文档查找见 [总索引](docs/README.md)。不要复制另一套规则或按会话创建交接文件。

- 只有具体大功能且现有 change 无法承载时才新建 OpenSpec；小修改直接在相关主题、Issue/PR 维护。
- PR 描述必须重新读取 Git/远端 PR：完整 base...HEAD 差异，加上 previous head→HEAD 的本次增量，记录 SHA；禁止用聊天历史代替修改范围。
- 后端运行/配置见 [backend](docs/backend.md)，结构见 [模块架构](docs/backend-architecture.md)，接口见 [契约](docs/backend-interface.md) 与 Controller/OpenAPI。
- Flutter 启动、SDK/Windows 修复和模拟器地址参数见 [mobile/README](mobile/README.md)；默认地址以 `mobile/lib/core/config.dart` 为准，切换 dart-define 后须重新运行。
- Web 的启动与构建见 `web/package.json`；当前验证、环境及限制见 [验证入口](docs/backend-validation.md)，接入边界见 [接口状态](docs/backend-interface-gaps.md)。

过程日志和截图写入被忽略的 `output/`。历史验证不能外推到当前代码，Mock、分析或编译通过不能单独证明功能完成。
