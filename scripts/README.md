# 脚本入口

在仓库根目录运行脚本，先阅读其参数与目标环境。运行日志和临时产物放 `output/`；实际凭据只放本地环境配置。

| 用途 | 脚本 |
| --- | --- |
| 后端启动、隔离验收及镜像冒烟 | `start-backend.ps1`、`test-backend.ps1`（可加 `-DockerMaven`）、`smoke-backend-image.ps1` |
| 核心 HTTP 场景与客户端专项 | `e2e-smoke.ps1`、`verify-scenario-runtime.py`、`test-member-b-live.ps1` |
| 备份与旧开发库副本升级 | `backup-backend.ps1`、`upgrade-legacy-lyb-clone.ps1`、`upgrade-ai-work-clone.py` |
| 独立本地展示环境 | `start-stage-demo.ps1`；真实客户端专项仍依赖该环境，不能按旧命名直接删除 |
| 年度场景库准备 | `prepare-annual-database.py`；见 [年度数据说明](../docs/annual-scenario-rebuild.md) |
| 独立数据基础设施打包、启动、验证 | `build-data-packages.ps1`、`start-data.ps1`、`verify-data.ps1`、`verify-data-lifecycle.ps1`、`data-integrity.sql`；见 [模型边界](../docs/data-infrastructure.md) |
| Flutter 缓存与 SQLite 环境修复 | `repair-flutter-pub-cache.ps1`、`prepare-flutter-sqlite.ps1` |
| AI 语料、模型与恢复专项 | `ai-work-acceptance-corpus.py`、`ai-work-deletion-markers.py`、`verify-ai-work-corpus.py`、`verify-ai-work-provider.py`、`verify-ai-work-restarts.py`、`verify-ai-ocr.py`、`verify-ai-memory-restore.ps1`、`evaluate-ai-development.ps1`；语料依赖见 `requirements-ai-work-acceptance.txt` |

这些脚本仍对应当前运维、专项验收、灾备或旧数据转换用途。副本升级工具仅适用于其支持的历史校验和，不代表可直接对现有云端业务库使用；部署与恢复步骤以相应运维文档为准。

移动端素材工具位于 `mobile/tool/`，保留当前 new_pack、柴犬包加工和桌面图标生成脚本。旧八屏原型的渲染/启动脚本和会同时覆盖旧开屏的 `process_app_icon.py` 已随过时产物清理。开屏由 Flutter Painter 与 Android 品牌矢量维护，见 [品牌设计](../mobile/docs/brand-splash-design.md)。
