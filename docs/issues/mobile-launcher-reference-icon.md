# 用户参考图替换Android桌面图标

- 优先级P2；分支HCJ；来源为用户2026-10-23提供的1024×1024 PNG。
- 范围：替换assets/icon_desktop.png和Android五档mipmap/ic_launcher.png，保留参考图完整构图，新增可复现生成脚本及开屏生图提示词。
- 当前AndroidManifest引用@mipmap/ic_launcher；现有process_app_icon.py会同时改写开屏资源，本批不调用它，另提供仅生成桌面图标的脚本。
- 不修改现有开屏图片、动画、路由、API或依赖；用户将另用生图AI生成开屏图。本次为现有图标替换，不新增产品能力。
- 验收：源图完整保留，五档PNG尺寸正确、Manifest资源链存在；实际桌面显示未运行验收。不执行测试、构建或设备，不提交推送，保留混合改动。

## 资源检查证据

- `python mobile/tool/generate_launcher_icon.py <用户PNG>`退出码0，生成五档PNG。
- Pillow读取mdpi至xxxhdpi尺寸分别48、72、96、144、192；源PNG与assets/icon_desktop.png字节比较True；Manifest解析icon仍为@mipmap/ic_launcher，命令退出码0。
- 已查看192px输出图，参考图完整构图保留。git diff确认6个既有图像文件修改，icon_splash.png与launch_image.png无差异；git diff --check退出码0。
- 以上仅资源检查，未运行构建、测试、安装或桌面验收。现有安装需下一次重新构建安装后才会使用新原生桌面资源，Flutter热重载不能据此证明图标已更新。
- 开屏正反提示词和图文布局建议保存在mobile/docs/launcher-icon-and-splash-prompt.md，本批不生成或替换开屏图片。
