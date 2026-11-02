## Why

用户已选定明黄、白色、深灰卡通桌面图标，要求自行以前端绘制设计开屏，布局简洁、少文字，并柔和衔接登录或首页。现有开屏是旧图卡片、纸纹与标语，动画结束直接移除；Android原生启动仍显示旧图片。

## What Changes

- Flutter CustomPainter绘制与用户图标同风格的白色圆润角色、眨眼、小爱心及少量短线；只显示应用名称。
- 角色轻微上移、标题淡入、覆盖层与真实页面交叉淡化，减少动态效果时使用短暂静态过渡。
- 保持底层会话恢复并行和组件位置稳定，不因开屏移除重新挂载会话恢复与路由。
- Android原生启动使用同一黄底和配套静态矢量角色，替换旧开屏图片引用。

## Capabilities

### New Capabilities
- `mobile-brand-splash`: 与桌面品牌统一的代码绘制开屏及柔和过渡。

### Modified Capabilities
- None.

## Impact

仅Flutter启动遮罩、原生启动资源和设计说明，不修改登录鉴权、导航、接口、数据库、依赖或全局主题。P1，本地Issue docs/issues/mobile-brand-splash.md；远程Issue未创建。保留HCJ混合改动。
