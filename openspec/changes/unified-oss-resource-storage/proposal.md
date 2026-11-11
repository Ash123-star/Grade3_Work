## Why

当前附件写入 PostgreSQL `attachments.data`，AI 解析、交付校验和清理直接依赖该字段；Flutter 图标、插画和纹理从安装包读取。用户要求统一使用已有阿里云 OSS 存储并实际接入调用，覆盖历史文件和静态素材，避免只上传文件但业务仍从旧位置读取。

## What Changes

- P1：将头像、任务附件、交付成果、AI 私有材料、制度/流程/模板原文件统一写入私有 OSS，并保持附件 ID、组织范围和版本校验。
- P1：统计导出 CSV、模板预填 DOCX/XLSX 等生成文件也先写入 OSS，再通过受控接口返回；后续下载重新校验当前来源权限。
- P1：应用运行时使用的图标、插画、纹理及字体等文件发布至带版本和哈希的 OSS 目录，通过白名单资源接口加载及缓存；许可证随资源同步并保留署名。Android 桌面图标、原生启动画面和法律署名保留必要打包副本，同时同步 OSS；系统启动阶段无法以网络资源代替原生文件。
- P1：新增可恢复的历史附件迁移和静态素材发布工具、事务失败补偿与到期对象清理；不得让数据库和 OSS 的部分成功形成不可追踪的残留。
- 服务端使用用户确认的 `panduola-work`、`cn-beijing`、`https://oss-cn-beijing.aliyuncs.com`；凭据只从服务端配置读取，不写入客户端、仓库或普通日志。
- 非目标：用户/组织、任务/日报正文、审核和 AI 文字等结构化业务数据仍由数据库负责；不改变任务和审核状态机，不增加客户端直传和任意 URL 下载。

## Capabilities

### New Capabilities

- `oss-business-files`：受控业务文件的 OSS 上传、下载、生成、历史迁移、失败补偿及清理。
- `oss-runtime-assets`：静态素材完整清单、版本化发布、双端实际加载、缓存、降级和许可证保留。

### Modified Capabilities

无。现有组织鉴权、审核和导出范围要求继续生效；新存储行为由上述能力扩展，活动变更 `ai-work-assistant` 的私有材料及保留策略不得被存储替换绕开。

## Impact

- 后端：`server/pom.xml`、`application.yml`、attachment、aiwork、procedure、analytics 模块及新增 Flyway 迁移（当前最高 V21，实施时复核编号），运行时 SpringDoc 及两份接口文档同步。
- 客户端：Flutter `shared/generated_assets.dart`、`shared/curated_assets.dart`、运行时字体和启动接入；Web 已有资源引用、附件及下载调用按实际清单接入，不把 Web 构建代码迁到对象存储。
- 部署：Compose、`.env.example`、静态发布/历史迁移工具、私有 Bucket/RAM 最小权限、备份与回滚说明。真实 `.env`、密钥和用户数据不得提交。
- 协作：D 主责存储及 AI/导出，E 主责契约、部署和客户端接入，A 协调静态加载及离线表现，C 协调任务附件绑定。Issue 编号、Sprint 和估算待关联，实施前创建/更新跟踪；不默认启动多代理。
- 验收：真实 OSS 写入和读回逐字节一致；覆盖头像、任务、AI 解析、交付、模板和导出链路；历史 ID/哈希不变；双端静态素材实际命中 OSS；跨公司/待确认/停用访问拒绝；验证隐私隔离及失败恢复两项非功能要求。规划文档不代表实现或真实 Bucket 验收完成。
