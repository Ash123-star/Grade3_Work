# image-2.5 UI 素材生成提示词

本文档用于生成当前 Flutter 项目的原创 UI 素材。目标风格参考成熟的卡通生产力 App：温暖、轻盈、精致，有插画和纸张质感，但业务信息仍然清晰、克制。

## 使用边界

- image-2.5 负责生成原创角色、状态插画、背景纹理和插画式图标。
- 圆角卡片、弹窗、底部弹层、Toast、图表、导航和业务列表必须由 Flutter 代码绘制。可以生成“组件样式参考板”，不能把截图当成生产组件。
- 不使用 Garfield、Doraemon、Pokemon 或任何其他已知角色、品牌标识、竞品截图作为提示词主体。
- 角色和插画保持原创，不能出现文字、Logo、水印、品牌 UI 或可识别的第三方角色特征。
- 所有图片生成后必须检查：透明背景是否真实透明、边缘是否干净、是否出现乱码文字、角色是否变形、是否混入品牌元素。

## 统一风格锁定词

把下面这段复制到每个资产提示词末尾。角色提示词还要重复同一段角色设定，避免不同批次生成出不同角色。

```text
Visual system: original friendly cartoon productivity-app illustration, polished mobile product quality, warm paper-like atmosphere, clean flat shapes with subtle 2.5D depth, rounded silhouettes, controlled thick olive outline, gentle offset shadow, small amount of paper grain, clear silhouette at 48dp scale, no visual noise.
Palette: cream #FFFDF4, mint #55D8A5, deep mint #319E7A, pale mint #E6FAEF, pale yellow #FFF4B8, coral #FFE1E1, sky blue #DDF1FA, dark text olive #43514B, existing brand orange #FF8A24 used only as a small accent.
Composition: centered subject, generous transparent padding, balanced negative space, reusable as a Flutter asset, no text, no logo, no watermark, no screenshot, no device frame.
Avoid: photorealism, glossy 3D plastic, neon colors, dark game UI, fantasy armor, excessive gradients, clutter, horror, sad facial distortion, extra limbs, duplicate objects, Chinese characters, English words, brand marks, copyrighted characters.
```

## 角色一致性设定

当前项目使用原创 Q 版角色。角色可以是圆脸猫、狗、兔子、熊、鸟、小精灵或其他自定义生物，不要求必须是人类。角色只用于欢迎、空状态、错误、成功、AI 反馈等位置，不替换任务、日志和审批的功能图标。

可以参考“慵懒猫、聪明小狗、害羞小兔”等高层性格方向，但不能把 Garfield、Doraemon、Pokemon 或其他已有角色的脸型、服饰、配色、道具、姿态和故事设定直接写进提示词。生成结果必须是可以独立命名的原创角色。

### 角色候选生成提示词

先用这条提示词生成 6 个候选角色，再从中选择一个作为项目主角色：

```text
Primary mascot: an original small round cream-colored puppy, short ears, one mint-green collar with a tiny coral tag, warm olive eyes, simple friendly face, compact body, four paws, no resemblance to any existing cartoon character.
Secondary mascot: an original small pale-gray cat with a mint scarf, used only as an occasional helper, same outline and proportions as the puppy.
Style/medium: friendly cartoon productivity-app illustration, rounded proportions, clean flat shapes, controlled olive outline, subtle paper grain, soft offset shadow, polished commercial app quality.
Color palette: cream, mint, pale yellow, pale blue and restrained coral; the existing brand orange may appear only as a small accent.
Composition/framing: six separate full-body candidates in a 3 by 2 grid, equal spacing, neutral cream background, no overlap, no text or labels.
Constraints: every character must be original and independently nameable; avoid any recognizable resemblance to any existing cartoon, mascot, game or animation character.
Avoid: photorealism, glossy 3D plastic, game character armor, excessive detail, logos, watermarks, letters, words, duplicate candidates.
```

### 选定角色后的锁定模板

把选定角色的具体外观写入下面的方括号，并在所有后续提示词中原样保留：

```text
Primary mascot: an original Q-style [species or creature], [body silhouette], [face and eye shape], [ear or head detail], [main body colors], [one small accessory], [personality cue]. Give this character a short original name: [name]. The design must not resemble any existing cartoon character.
Secondary mascot: optional original helper character, [species], [two color accents], [simple accessory], used only in AI help or success feedback scenes.
```

可选角色方向示例：

```text
Primary mascot: an original round orange-cream cat with a tiny mint neckerchief, one asymmetric ear, sleepy but kind olive eyes, a small coral star tag and a compact bean-shaped body. The character is relaxed, observant and helpful. Give this character the original name "Mimi". The design must not resemble any existing cartoon character.
```

```text
Primary mascot: an original small blue-gray rabbit with a cream belly, short rounded ears, a mint messenger pouch and bright olive eyes. The character is curious, organized and energetic. Give this character the original name "Nono". The design must not resemble any existing cartoon character.
```

```text
Primary mascot: an original soft cloud-like creature with a cream body, mint feet, two coral cheek marks and a tiny calendar-shaped badge. The character is calm, supportive and slightly playful. Give this character the original name "Yoyo". The design must not resemble any existing cartoon character.
```

生成角色时追加以下约束：

```text
Keep the exact same mascot species, face proportions, silhouette, accessory, colors, outline thickness and body scale across every image. Show the full body unless the prompt explicitly asks for a close-up. Change only the action, expression or scene required by the prompt. Do not add clothing, accessories, species traits or colors that were not specified.
```

## 1. 业务图标

### 生成策略

最终业务图标建议一图一文件，统一为 1024×1024 透明 PNG；不要直接把一张包含八个图标的图裁成生产资源。先生成一张联系表确认风格，再按相同风格分别生成单个图标。

### 联系表提示词

```text
Use case: ui-mockup
Asset type: internal illustration style board for a mobile enterprise workspace
Primary request: create an 8-tile icon style board showing eight separate original illustrated business icons: task clipboard with check mark, work log notebook with pencil, monthly calendar with one dot, approval stamp with check, AI sparkle chat bubble, two-person member group, notification bell, and map with connected nodes.
Style/medium: use the unified visual system below; each icon is a compact colored object inside a rounded squircle tile, consistent outline, consistent shadow, consistent scale.
Composition/framing: 4 columns by 2 rows, equal spacing, each tile isolated, no labels and no text.
Constraints: the icons must remain recognizable at 48dp, use orange only as a tiny accent, leave enough empty space around every tile.
```

### 单图标模板

```text
Use case: stylized-concept
Asset type: Flutter business icon, transparent PNG, 1024x1024
Primary request: one original illustrated [ICON SUBJECT], designed for a friendly enterprise productivity app. The object must be immediately recognizable at small size and use one simple central silhouette.
Subject: [ICON SUBJECT]
Style/medium: unified visual system; compact flat illustration, rounded geometry, controlled olive outline, subtle paper texture, soft offset shadow.
Composition/framing: centered object, front-facing three-quarter view, no surrounding scene, 18 percent transparent padding on every side.
Constraints: no text, no numbers, no logo, no human face inside the icon, no duplicate objects, no clipped edges.
Avoid: [paste unified Avoid block]
```

建议的 `[ICON SUBJECT]`：

- task：mint clipboard, two checklist rows and one coral check badge
- log：cream notebook, mint spine and small orange pencil
- calendar：rounded calendar with one mint dot and one pale-yellow date marker
- approval：rounded approval stamp with a clear check seal
- ai：sparkle chat bubble with three mint and coral sparkles
- members：two simple person silhouettes with one small coral status dot
- notification：rounded bell with a small mint notification dot
- map：friendly folded map with three connected mint nodes

## 2. 角色状态插画

每个状态生成 1024×1024 透明 PNG。角色姿态、脸型、领巾和轮廓必须保持不变，只改变动作和道具。

### 空状态

```text
Use case: illustration-story
Asset type: empty-state illustration, transparent PNG, 1024x1024
Primary request: the primary mascot sits beside an open cream notebook with one tiny mint sprout, gently waving to invite the user to create the first record. The mood is calm and encouraging, never childish or noisy.
Subject: primary mascot, open notebook, tiny sprout, one small pale-yellow sparkle.
Composition/framing: centered full-body composition, objects grouped in the lower half, generous transparent margin, suitable for a list page empty state.
Lighting/mood: soft daylight, friendly, quiet.
Constraints: no text, no UI frame, no buttons, no watermark.
```

### 加载 / AI 处理中

```text
Use case: illustration-story
Asset type: AI processing state illustration, transparent PNG, 1024x1024
Primary request: the primary mascot is thinking beside a rounded mint chat bubble, with three small orbiting sparkles and a tiny rotating paper card. The pose must suggest processing without looking worried.
Composition/framing: centered full body, open space around the sparkles for a Flutter looping animation, no background scene.
Lighting/mood: soft mint glow, focused and reassuring.
Constraints: no text, no letters, no numbers, no UI controls, no logo.
```

### 提交成功

```text
Use case: illustration-story
Asset type: success feedback illustration, transparent PNG, 1024x1024
Primary request: the primary mascot smiles and holds a rounded cream confirmation card with a large abstract mint check seal, with three restrained coral and yellow confetti pieces.
Composition/framing: centered full body, check seal clearly visible, keep confetti sparse so it remains suitable for a business app.
Lighting/mood: warm, relieved, celebratory but professional.
Constraints: the card must contain no text, no number and no logo.
```

### 错误 / 网络失败

```text
Use case: illustration-story
Asset type: error-state illustration, transparent PNG, 1024x1024
Primary request: the primary mascot calmly holds a small pale-coral warning card with an abstract exclamation symbol, while a short dotted connection line stops before reaching it. The character looks helpful, not frightened.
Composition/framing: centered full body, warning card readable as a shape at small size, generous transparent padding.
Lighting/mood: gentle and constructive, suitable for a retry state.
Constraints: no text, no scary expression, no broken-glass effect, no red-dominant palette.
```

### 欢迎 / 首次进入

```text
Use case: illustration-story
Asset type: welcome illustration, transparent PNG, 1536x1024
Primary request: the primary mascot stands on a soft cream paper island with a mint notebook, a small calendar card and three abstract sparkles. The scene introduces a friendly work-planning app and leaves large clean negative space on the right for Flutter-rendered copy.
Composition/framing: mascot and objects grouped on the left third, empty space on the right, no text in the image.
Lighting/mood: warm morning light, optimistic, polished onboarding artwork.
Constraints: no device frame, no UI screenshot, no logo, no text.
```

## 3. 背景纹理和装饰

背景只承担氛围，不能影响日志、审批和日历内容的阅读。建议生成无角色的可平铺纹理，代码中用低透明度叠加。

### 纸张点阵

```text
Use case: stylized-concept
Asset type: seamless mobile app background texture, 2048x2048 square
Primary request: warm cream paper texture with a very subtle mint dot grid, tiny rounded corner marks and occasional pale-yellow specks, evenly distributed and low contrast.
Composition/framing: seamless tile, no focal point, no characters, no text.
Constraints: background contrast below 8 percent, no large shapes behind content, no gradients that compete with cards, no watermark.
```

### 页面角落装饰

```text
Use case: stylized-concept
Asset type: transparent decorative corner doodle, 1024x1024
Primary request: a small set of original rounded paper, leaf and sparkle doodles in mint, pale yellow and coral, arranged as a loose top-right corner decoration.
Composition/framing: decoration occupies only the outer 30 percent, large transparent center, designed to sit behind a page header.
Constraints: no text, no character, no logo, no dense pattern.
```

## 4. 组件和图表参考板

这类提示词只用于确认视觉方向，实际组件必须在 Flutter 中实现。

### 组件样式参考板

```text
Use case: ui-mockup
Asset type: high-fidelity visual reference board for Flutter component implementation
Primary request: show a polished mobile enterprise workspace component board containing a rounded metric card, a compact list row, a segmented control, a modal dialog, a bottom sheet, a toast and a primary button.
Style/medium: cream paper background, mint primary surfaces, pale-yellow and pale-blue state surfaces, coral warning accent, 12 to 20px rounded corners, 1.5px olive borders, soft offset shadows, restrained cartoon mascot decoration only in the empty and success samples.
Composition/framing: clean vertical specimen board, consistent spacing, no device frame, no brand name.
Text (verbatim): ""
Constraints: use blank text bars and abstract placeholder shapes instead of words; do not generate Chinese text; do not use real app screenshots.
```

### 图表卡片参考板

```text
Use case: productivity-visual
Asset type: chart card style reference for a Flutter productivity app
Primary request: a set of three rounded chart cards: mint line chart for weekly work hours, coral and pale-yellow donut chart for task categories, and pale-blue bar chart for daily activity.
Composition/framing: each chart is simple, legible and surrounded by generous padding; use abstract placeholder bars for labels and numbers, no readable text.
Style/medium: same cream paper, olive outline, soft shadow and controlled color palette as the unified visual system.
Constraints: no fake dashboard screenshot, no tiny unreadable labels, no 3D chart, no gradients that hide data.
```

## 5. 动效状态生成与实现

image-2.5 适合生成静态关键帧或动效分镜参考，不能直接替代 Flutter 动画文件。建议流程：

1. 先生成一张主角色静态图，作为所有状态的参考图。
2. 再生成 6 格 AI 处理中分镜，只改变耳朵、眼睛、纸卡和闪光点的位置。
3. 在 Flutter 中使用 `AnimatedSwitcher`、`TweenAnimationBuilder`、`ScaleTransition` 和 `FadeTransition` 重建动效。
4. 提供 reduced-motion 分支：减少位移和缩放，只保留淡入淡出和状态变化。

### 动效分镜提示词

```text
Use case: illustration-story
Asset type: six-panel animation storyboard reference, 1536x1024
Input images: Image 1 is the approved primary mascot reference; preserve the character exactly.
Primary request: six evenly spaced panels showing the same primary mascot processing an AI request. Frame 1 is idle, frames 2 to 5 show three sparkles orbiting slowly and a small paper card rising by a few pixels, frame 6 returns to a calm idle pose.
Composition/framing: identical camera, identical body scale, identical background and lighting in every panel, no text.
Constraints: only the sparkles, eyes and paper card may change position; no new props, no extra limbs, no character redesign.
```

## 6. 尺寸、命名和导入建议

| 资产 | 推荐尺寸 | 文件命名 | Flutter 用法 |
| --- | --- | --- | --- |
| 业务插画图标 | 1024×1024 | `icon_task_v1.png` | `Image.asset` 放入统一 `AppIconTile` |
| 角色状态 | 1024×1024 | `mascot_empty_v1.png` | 空状态、错误、成功、AI 状态 |
| 欢迎插画 | 1536×1024 | `welcome_workspace_v1.png` | 首屏或引导页背景插画 |
| 纸张纹理 | 2048×2048 | `paper_mint_dots_v1.png` | 低透明度 `DecorationImage` |
| 角落装饰 | 1024×1024 | `doodle_corner_top_right_v1.png` | 页面背景装饰 |
| 动效分镜参考 | 1536×1024 | `mascot_ai_storyboard_v1.png` | 只作实现参考，不直接运行 |

推荐目录：

```text
mobile/assets/generated_ui/
  icons/
  mascot/
  backgrounds/
  references/
mobile/assets/licenses/generated-ui-sources.json
```

## 7. 授权和来源记录模板

每个进入仓库的生成资产都要在 `mobile/assets/licenses/generated-ui-sources.json` 中登记：

```json
{
  "asset": "mascot_empty_v1.png",
  "path": "mobile/assets/generated_ui/mascot/mascot_empty_v1.png",
  "source_type": "ai_generated",
  "model": "image-2.5",
  "generated_at": "2026-10-13",
  "prompt_file": "mobile/docs/image-2.5-ui-asset-generation-prompts.md",
  "prompt_section": "2. 角色状态插画 / 空状态",
  "reference_images": [],
  "third_party_brands_or_characters": [],
  "license_note": "Original project asset generated for this project. Review the applicable image model terms and retain this record with the asset.",
  "review": {
    "transparent_background_checked": true,
    "text_and_logo_checked": true,
    "copyright_character_checked": true,
    "approved_for_product": false
  }
}
```

`approved_for_product` 只有在视觉验收、透明边缘检查、无文字检查和项目负责人确认后才能改为 `true`。如果使用 OpenMoji、Phosphor 或其他外部素材，仍需单独登记官网/GitHub 来源、版本、许可证和署名要求，不能把它们混入 AI 生成资产的来源记录。

## 8. 生成顺序

1. 先生成主角色参考图和 5 个状态：空、错误、处理中、成功、欢迎。
2. 生成 8 个业务图标，并在 360dp、390dp、412dp 截图中检查小尺寸识别度。
3. 生成纸张纹理和角落装饰，确认内容区对比度后再接入页面。
4. 用组件和图表参考板统一 Flutter 的卡片、弹窗、Toast 和图表 token。
5. 最后制作动效分镜并用 Flutter 原生动画实现，检查 reduced-motion 和无障碍语义。

