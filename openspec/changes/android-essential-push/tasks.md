## 1. Proposal and contracts
- [x] 1.1 关联Issue #86，完成阿里云路线/范围设计并通过OpenSpec严格校验
- [x] 1.2 新增设备/偏好/投递迁移和本人API，待确认仅接收本人入职结果，记录契约和回滚

## 2. Backend delivery
- [x] 2.1 复用outbox原子入队、白名单、会话lease/权限/版本/有效期检查及有限重试
- [x] 2.2 接入官方阿里云SDK、独立配置开关、脱敏摘要和供应商受理状态，缺配置不假成功
- [x] 2.3 任务事件补动作元数据，截止阶段覆盖真实参与人且去重/不补错过窗口

## 3. Android and Flutter
- [ ] 3.1 官方SDK、厂商参数入口、Android13权限、三个私密通知channel及初始化开关；官方接入核对发现仍在MainActivity初始化，须改为Application初始化并维持用户同意后的注册门控，再验证
- [x] 3.2 本人通知设置、分类/免打扰/系统状态、登录设备绑定及退出/换号清理
- [x] 3.3 前后台/冷启动点击缓存、身份恢复、服务端授权和安全详情跳转，不重复展示SSE通知

## 4. Verification and delivery
- [x] 4.1 单元测试覆盖白名单、日期/静音/过期/重试及非法输入
- [x] 4.2 真实PG+受控供应商端到端覆盖业务入口/数据/投递、权限/撤销/重复/换号
- [x] 4.3 Flutter设置/权限拒绝/点击/绑定测试、受影响分析与Android编译验证
- [x] 4.4 同步接口/数据库/部署配置/隐私文档，记录实际验证和非功能安全/可靠性证据，严格校验
- [x] 4.5 核对base/head完整Git差异，提交推送并创建草稿PR，明确依赖和外部验收限制

## 5. External acceptance
- [ ] 5.1 配置阿里云EMAS应用、服务端RAM/STS、厂商通道和正式签名（用户安全环境提供）
- [ ] 5.2 真机前台/后台/锁屏/进程回收/离线恢复送达及冷启动，验证系统通知关闭和设备分类设置

草稿PR：[ #87 ](https://github.com/Ash123-star/Grade3_Work/pull/87)。5.1/5.2没有真实证据不得勾选；本地受控测试不代表云端送达，任务未全部完成不归档。

后端已按用户要求部署提交 `3fec52f`，实际库V34成功，推送保持关闭；运行、备份和回滚见 [systemd部署说明](../../../docs/cloud-systemd-deployment.md)。本次只启动服务器，Android初始化修正和5.1/5.2继续待办。初始化约束依据 [阿里云Android SDK接入](https://help.aliyun.com/zh/document_detail/434660.html)：PushServiceFactory.init须在Application主线程且覆盖channel进程，不能放在Activity；注册联网仍须在用户同意后执行。

APK构建补充：正式Release压缩被推送SDK引用的可选类缺失阻塞（华为系统/分析类、org.android.netutil、BouncyCastle）；发布前须核对依赖与官方混淆规则，不能仅隐藏全部警告。本次仅交付关闭Java压缩、使用调试证书的Release联网测试包，剥离Flutter图片/字体并保留原生必要资源和许可证；签名/包内容检查通过，本机模拟器启动失败，安装和真机界面未验收。详细证据见 [后端验证的APK补充](../../../docs/backend-validation.md#阿里云-android-必要通知issue-86)，3.1/5.1/5.2不勾选。
