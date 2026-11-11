# OSS资源部署与验收

关联Issue：[#79](https://github.com/Ash123-star/Grade3_Work/issues/79)，OpenSpec `unified-oss-resource-storage`。使用阿里云私有Bucket `panduola-work`，北京地域 `cn-beijing`，HTTPS Endpoint `https://oss-cn-beijing.aliyuncs.com`。

## 配置与权限

服务端 `deploy/backend/.env` 配置 `OSS_BUCKET/OSS_REGION/OSS_ENDPOINT/OSS_PREFIX`（默认 `workpanel`），以及 `OSS_ACCESS_KEY_ID/OSS_ACCESS_KEY_SECRET`，短期凭据另设 `OSS_SECURITY_TOKEN`。也可在ECS使用 `OSS_ROLE_NAME` 的实例角色；两种方式择一。不向客户端分发密钥、不提交真实环境文件。Compose已透传配置，修改后重新创建API容器才能生效。

RAM用户只授予Bucket的 `workpanel/*` 对象读写删除权限；用于迁移盘点时再授予该前缀的ListObjects。不应修改整桶公共读；对象上传显式private。公开产品素材只能通过服务器白名单接口访问，业务下载先检查当前会话、公司和业务权限。无配置/供应商失败返回503，不静默回退数据库。SDK诊断日志关闭，错误响应不包含凭据和供应商异常正文。

## 存储与实际调用

- 头像、任务附件、交付、AI材料、制度流程原文件均经attachment的存储端口读写。新文件正文只在OSS，元数据在数据库。
- CSV导出和模板预填产物先写OSS并读回；接口仍返回原二进制响应。`GET /api/generated-files/{id}`支持24小时内再次读取，每次核对本人身份及来源权限/版本；配置 `GENERATED_FILE_HOURS` 支持1–168小时。附件兼容下载入口也执行同一来源检查。
- 图片、SVG、纹理、字体、许可证发布为不可变manifest。除 `mobile/assets` 外，还从实际Flutter构建清单纳入依赖包OpenMoji图片、Material/Forui图标字体、Inter字体及依赖许可证。Flutter `DefaultAssetBundle`接管 `assets/`、`packages/`、`fonts/` 资源，FontLoader按完整字体清单注册远程字体，先校验缓存/远程文件，失败才回退安装副本；Web加载同清单的标题字体。原生桌面图标和系统启动画面必须保留安装副本，同时发布OSS副本；JS/CSS、着色器、包内HTML执行入口仍按应用发布。
- 业务文件使用 `workpanel/business/{companyId}/{id}`；静态文件使用 `workpanel/static/{release}/{hash}/{logicalPath}`。客户端仅知道公开逻辑路径，不能传任意OSS Key。

## 运维工具

先完成后端构建并启动新版本，Flyway执行新增V33；不能直接在未升级数据库上调用发布/迁移命令。线上已存在V22–V30，不能占用这些编号，也不能用旧分支应用覆盖线上新功能；上线前须将本次变更整合到实际部署基线并验证。工具读取指定环境文件，不启动业务定时任务，不输出密钥。输出报告保存在Git忽略的 `output/oss`。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/prepare-oss-assets.ps1 -Flutter D:/flutter/bin/flutter.bat
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command inventory -Release release-20261111
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command probe
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command publish -Release release-20261111 -Apply
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command migrate
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command migrate -Apply
```

先按项目Flutter SDK解析依赖，再执行 `prepare-oss-assets`，从真实构建的FontManifest及包素材准备忽略目录 `output/oss/flutter-assets`；缺少该目录时仓库盘点/发布拒绝继续，避免漏发依赖图标/字体。部署时将此目录和应用素材作为同批发布输入传入服务器，不能只复制Java JAR。`inventory`完整盘点素材及SHA-256、数量、总大小；`publish`不带Apply仅预览，不发布。任何文件上传/读回失败均不切换当前版本；同版本内容不允许覆盖。旧版manifest继续可读。

迁移前备份PostgreSQL，并保留原件清单。`migrate`支持分批和重复执行：历史ID及引用不变，先记录意图并上传/读回校验，再以行版本切换provider；失败仍可读数据库原件。已清理和过期文件跳过；迁移成功仍暂保留数据库原件，不将有副本误报为“新文件正文存数据库”。

全量报告和业务链路核对后，才可独立清除数据库副本；工具要求提供已有备份文件，操作者负责验证该备份可恢复：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/oss-resources.ps1 -Command purge -BackupFile D:/backups/workpanel.dump -Apply
```

回滚优先保留兼容OSS的后端并切换静态版本指针。要回到仅支持bytea的旧应用，须先停写，执行 `restore -BackupFile <已验证备份> -Apply` 将OSS原件校验恢复到数据库，再部署旧应用；禁止直接删除OSS对象或回滚已发布Flyway文件。

## 故障恢复与清理

上传先提交PENDING意图，上传/数据库READY提交失败时不报告成功；超时PENDING对象进入持久化删除任务。清理与绑定均锁附件行，DELETING不接受新绑定。删除网络调用在事务外执行，失败保留任务并退避，完成后才标DELETED。私人AI原件继续遵循既有30/90天保留规则，正式任务/交付/制度/头像仍引用时保留。生成文件默认24小时过期；未绑定OSS上传超过一天进入清理。

迁移意图、发布版本和删除任务可通过数据库定位；不在日志打印私有Key、材料正文或凭据。中断的历史迁移重新运行即可继续；发布失败的不可达静态对象可重试同版本发布，旧完整版本持续生效。

## 验收要求与限制

跨分支整合（Issue #82）：保留每日事项范围/颜色迁移V31，创始人审核停用迁移为V32，OSS迁移为V33，避免三个分支的V31发生碰撞。已发布V30及之前迁移正文不变。若某个开发库已执行分支独立版本的V31，必须先核对flyway_schema_history的脚本和校验和，再从已验证备份安排升级；禁止自动repair、删除历史或将三个同号迁移混用。

本次整合工作树基于GitHub主分支3f9eb2d及线上已使用的消息优化分支aa70b35，新增迁移V33。原19db6f3工作区和其中用户改动保持原样；旧分支的测试失败不应直接套用为新基线结果。新版统计导出仍经AnalyticsQuery/Repository生成一致快照，关闭快照事务后才写OSS并重新鉴权；资料更新沿ProfileService/Repository，保留新版手机号/组织范围规则。

后端单元及真实HTTP/PostgreSQL测试显式注入可控对象供应商替身，验证权限、完整性、失败恢复、历史迁移和原子发布；替身不代表真实OSS通过。`probe`使用独立verification随机对象，验证真实写入/读回一致、匿名读取403和删除，最后清理测试对象。

最终报告必须分别记录后端/Flutter/Web检查、真实OSS探针、实际发布清单、历史文件迁移结果与客户端实际网络渲染。没有真实前后端部署及客户端链路证据时，不报告生产上线或全量迁移完成。不得把安全探针通过当作全部用途和客户端渲染已验收。
