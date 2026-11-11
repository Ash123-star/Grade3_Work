## ADDED Requirements

### Requirement: Complete versioned OSS asset publication
优先级P1，范围为应用内图标、插画、纹理、字体、许可证及原生图标/启动素材副本。发布工具 SHALL 盘点完整实际资源清单，将逻辑路径、SHA-256、类型、大小、来源和用途写入版本化manifest，并把文件同步至OSS；整版上传并读回验证完成前 MUST 不激活新版本。原生必需资源可保留打包副本并明确报告，不能将应用代码或敏感环境文件当素材发布。

#### Scenario: Complete successful publication
- **WHEN** 运维发布完整资源版本且所有对象校验成功
- **THEN** 当前版本原子切换，清单每项均可从OSS读回，旧版保持不可变，数量和总大小有可核对报告。

#### Scenario: Partial upload or conflicting publication
- **WHEN** 任一对象上传/哈希校验失败或并发发布版本冲突
- **THEN** 新版不激活，旧版持续可用，返回明确错误并允许安全重试，不留下半版清单供客户端使用。

### Requirement: Public asset gateway cannot expose private files
优先级P1，范围为双端登录前后静态素材读取。服务端 SHALL 提供白名单manifest和版本化素材接口，只允许准确匹配已发布静态清单的对象；MUST 拒绝任意Bucket、对象Key、URL、目录穿越和业务前缀，正确返回内容类型、ETag和缓存策略，Bucket保持私有。

#### Scenario: Product artwork is available before login
- **WHEN** 客户端请求已发布的登录页图标或字体
- **THEN** 无需业务登录也可经素材接口读取相同哈希的OSS文件，可按不可变版本缓存，不返回OSS凭据。

#### Scenario: Forged path attempts to read business material
- **WHEN** 请求包含父目录、编码绕过、伪造版本、未发布路径或业务文件标识
- **THEN** 返回404且不请求任意OSS对象，不泄漏私人材料或对象存在性。

### Requirement: Runtime clients actually consume OSS assets
优先级P1，范围为Flutter运行时图片/SVG/纹理及可远程加载字体，Web实际存在的同类素材。客户端 SHALL 通过统一加载器使用已发布清单读取OSS素材，校验和缓存资源；图片保持原尺寸、交互、语义和布局。Android桌面图标和原生启动图 MUST 保留系统要求的打包文件并同时同步OSS，不宣称原生安装资源由网络替代。

#### Scenario: Fresh installation loads remote artwork
- **WHEN** 清空缓存的客户端联网打开含图标、插画、纹理及字体的界面
- **THEN** 实际请求已发布素材接口并获得OSS字节，界面正常显示，运行证据可区分网络命中和打包回退。

#### Scenario: Offline or corrupt asset response
- **WHEN** 设备离线、manifest不可用、资源超时或哈希不符
- **THEN** 不使用损坏资源，受限等待后使用最后验证缓存或打包降级，核心登录/导航/任务操作不因装饰素材永久阻塞，支持恢复联网后重试。

### Requirement: Licenses and client cache remain safe
优先级P1，范围为公开产品素材和私有业务文件的缓存边界。系统 SHALL 同步并保留素材来源及许可证，OpenMoji如存在继续展示CC BY-SA 4.0署名；公开静态缓存 MUST 不复用为私有附件缓存，不在公共manifest中写入用户文件和个人信息，许可证在离线时仍可阅读。

#### Scenario: Attribution is retained across publication
- **WHEN** 发布新版本并在线或离线查看应用许可证
- **THEN** 版权来源及适用署名可读取，素材原许可证不因迁移丢失，manifest无业务文件或用户数据。

#### Scenario: Private download requested through static cache
- **WHEN** 用户尝试以业务文件ID或退出登录前的业务下载路径访问公开静态缓存
- **THEN** 不能命中公开资源，后续业务下载仍经过当前权限校验，公共缓存中没有私人原件。
