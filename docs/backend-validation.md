# 后端验证与验收入口

本文件维护验证方式与当前结果入口，不逐轮堆叠环境安装和历史交付流水账。最新一次完整前后端联调的基线、命令、退出码及限制见 [2026-10-30 联调记录](frontend-backend-integration-validation-2026-10-30.md)。旧版本验证可从 Git 历史和相关 OpenSpec 查询。

## 验证方式

在仓库根目录执行；需要 Java 21、Maven 与 Docker，环境和参数以脚本为准：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1
# 本机资源受限时使用 Docker Maven
powershell -ExecutionPolicy Bypass -File scripts/test-backend.ps1 -DockerMaven
```

脚本使用隔离资源，不应将实际业务数据库作为测试目标。镜像冒烟、真实 HTTP 场景、专项验证和灾备工具见 [脚本索引](../scripts/README.md)。需要维护 OpenSpec 时执行规范校验；简单修改按 [开发流程](development-workflow.md) 选择受影响检查，不为验证过程单独创建文档或 change。

## 当前待处理项

2026-10-30 联调记录中的后端完整回归退出 1：442 项运行，49 失败、1 错误；部分隔离 HTTP 场景与客户端读取烟测通过，不能替代全量失败项。需逐项区分夹具过期与真实产品缺陷，保留权限、版本及并发保护。目标环境、设备、外部 DeepSeek/OCR、性能与无障碍仍有未验收范围，具体以该记录为准。

历史测试 JVM 等待退出后被强制结束的诊断仍见 [专项安全回归](member-b-security-regression.md)；构建成功不能据此宣称优雅退出已验证。旧数据库转换只允许按工具支持的已知历史先备份、恢复副本再校验，不改写已发布 Flyway 脚本或直接 repair 业务库。

后续结果更新现有主题文档或 Issue/PR，必须提供代码基线、环境、命令、明确退出码、结果及限制。过程日志与截图放被忽略的 `output/`。本次仓库清理没有运行功能测试，也没有部署或数据库修改。
