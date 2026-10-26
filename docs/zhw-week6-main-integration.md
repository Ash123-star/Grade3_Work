# PR #33 主线整合记录

日期：2026-10-23。Issue #32；Draft PR #33。来源：zhw 8b170e3 与 main 808d9d6。

## 范围

- 获取主线时发现本机Clash已运行，但Git未使用本地7897代理。通过单次命令http.proxy获取成功；未写入全局代理配置。
- 逐段解决API_CONTRACT.md、log_edit_window.dart、repository.dart、detail_pages.dart四个冲突，不重写已有提交历史。
- 保留主线页面/参与人显示与本分支的日志窗口、评论回复、分页条件和错误映射；日志详情只保留一个截止定时器，保留窗口模型submitted接口。
- HCJ participantIds/tagId映射为后端participants/labelId，服务端label映射真实名称/颜色；保留旧任务写入的兼容路径。
- 登记标签及任务评论列表入口、任务评论POST及幂等键。日志评论提供actorName以兼容主线PublicComments。
- smoke适配任务创建先审核、再生效及任务评论幂等约束。

## 验证

本批在Windows、Flutter本机SDK、main 808d9d6整合后的工作树执行。以下命令均取得明确退出码0。

| 检查 | 命令与结果 | 本地证据（忽略目录，不提交） |
| --- | --- | --- |
| 分析 | `dart analyze`：0 error、0 warning、8 info（主线既有弃用/风格提示） | `output/zhw-main-analysis.log` |
| Mock全量 | `flutter test --no-pub --dart-define=USE_MOCK=true --concurrency=2`：323通过、3跳过（需要显式开启的真实服务专项） | `output/zhw-main-mock-verified.log` |
| 正式模式契约 | `flutter test --no-pub --dart-define=USE_MOCK=false --concurrency=2 <24个契约/相关测试文件>`：218通过 | `output/zhw-main-formal-final.log`，文件清单`output/zhw-main-formal-files.txt` |
| 规格 | `openspec.cmd validate --all --strict`：38项通过 | 控制台退出码0 |
| smoke脚本语法 | PowerShell Parser解析`scripts/e2e-smoke.ps1`：无语法错误 | 控制台退出码0 |
| 差异 | `git diff --check`：无空白错误；无未解决冲突路径 | 控制台退出码0 |

命令通过SDK内的dart.exe及flutter_tools.snapshot执行，与上述Flutter命令等价。Flutter测试按顺序运行，避免共享构建目录的资源竞争。

首轮检查发现自动合并产生的重复departmentId参数，已移除；第一次完整Mock回归为322通过、3跳过、1失败（旧测试仍断言participantIds）。按实际后端participants字段修正断言后，全量复跑取得上表结果。保留首轮日志`output/zhw-main-mock-final.log`，不将失败轮次算为通过。

正式模式测试使用HTTP契约夹具，不属于真实后端联调。本次未启动最新后端、未执行更新后的smoke实跑，也未重新构建APK或验收Android设备。

## 边界

- 旧报告docs/zhw-week6-validation.md的137后端测试、24组smoke和真实Repository证据仅属于dc00e2b，不能充作本次808d9d6整合后的真实证据。
- 标签选择器静态数据替换、任务评论完整页面读取、新任务审核全链路、旧字段依赖完全移除及Android真机仍由OpenSpec 2.3/2.4跟踪；不能据静态检查、Mock或协议夹具声称完成。
- 无新增服务端业务改动或迁移；主线已有迁移随merge保留。
- 用户指定的压缩包、解压目录、失败克隆目录、镜像包和week6分工文件不纳入提交。

## 交付状态

- 整合提交`7277592f13b49c019cade783afab143c11ba9fb1`已推送至origin/zhw，两个父提交为原zhw `8b170e3`及main `808d9d6`。
- 已读取远端PR #33确认head为7277592、base为808d9d6、draft=true；未合并PR。
- GitHub连接器更新PR正文返回`403 Resource not accessible by integration`，正文未更新。需作者按本报告补充PR的验证结果及未完成事项；原有PR正文仍可能保留“冲突待处理”的旧状态。
- OpenSpec 3.1已完成；3.3的代码推送与本地验证已完成，PR正文更新因权限阻塞保持未勾选。2.3/2.4继续保留未完成。
