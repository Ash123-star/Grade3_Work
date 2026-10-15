# 本地 Issue：卡通 UI 截图缺陷修复

- 日期：2026-10-14；优先级：P1；承接阶段3 Issue #6。
- 背景：九张截图显示选中态紫色、顶部组件分离和快捷入口错位、四卡过长、月历摘要过窄、详情/AI/我的入口缺乏图案与层次。
- 范围：Flutter 视觉层、用户本地素材处理和公共组件；保持业务、权限、导航、接口、数据库和原始素材。
- 验收：统一资源解码和透明检查，360/390/412dp、1.5字体实际渲染，无溢出/遮挡，48dp目标及语义，通知筛选/详情/月历导航正常，错误和无权限恢复有效。
- 关联：`openspec/changes/tuantuan-ui-migration/` tasks 5.1—5.7。
- 技术路线及假设：见对应 design.md；真实无文字组件皮肤+九宫格伸缩+Flutter 内容，系统加粗标题，月历等分七列完整显示一周，不横向滚动；类型标记与两行标题简写保留可读内容。
- 未完成：实施与统一验收待执行；原生设备/TalkBack/真实服务不由客户端 Mock 验收替代。
- 工作区边界：启动时有未跟踪资源与脚本，保留来源并只提交可确认属于本批的文件；远程关联/交付依据最终工作区与验证结果处理。

- 2026-10-15 追加验收：所有用户可见页面与状态必须实际接入素材；标题使用离线加粗圆体，验收关联 tasks 6.1—6.3。
# 2026-10-15 最新验收补充

标题必须加载有许可的本地粗圆体，不能只设置系统字体别名。月视图七列同屏，日期与 +N 共用行，单元高宽比例均衡；记录只使用颜色标签和可读的单行标题，删除“任/日”前缀与上方类型提示，保留文字缩放和当天完整列表。弹窗内容需使用不透明底色；统计比例值保持单行；开屏首帧不得依赖 MaterialApp 内部主题或 MediaQuery。关联 tasks 5.5、6.1–6.4。

## 2026-10-15 本批验证记录

- 已实现：弹窗正文不透明底色、统计比例单行缩放、月历去类型前缀/提示、按字高留足日期格空间、选中日期仅用代码颜色、GenSen Rounded TW 本地字体、裁切后 launcher/native/Flutter 图标和独立开屏上下文。
- 验证：`flutter analyze`、`flutter test test/calendar_agenda_test.dart`、`flutter test test/tuantuan_screenshot_repair_test.dart`、`flutter test test/management_analytics_http_test.dart`、`openspec.cmd validate --all --strict` 均通过；Android debug APK 在 Pixel_8_Pro 模拟器冷启动，检查日志无 `No Directionality widget found`、Flutter 异常或布局溢出。
- 尚未完成：5.3、5.4 与 6.1、6.3 的全页面素材迁移和逐路由素材覆盖审计仍未完成；真实设备、TalkBack 和真实后端验收仍未执行。

