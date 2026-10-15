---
name: flutter-ui-design
description: Design and implement cohesive Flutter mobile UI systems from approved visual references, with HTML prototype comparison, Material 3 tokens, accessible states, and asset licensing checks.
metadata:
  short-description: Flutter UI design and prototype workflow
---

# Flutter UI Design

Use this skill when the user asks to redefine a Flutter product's visual language, compare reference products, create a high-fidelity HTML prototype, or implement a polished mobile UI.

## Workflow

1. Read `AGENTS.md`, `方案.md`, the current mobile route tree, and existing design documents.
2. Treat visual redesign as a separate approved batch. Do not delete old assets or change Flutter theme code until the replacement direction is selected, unless the user explicitly asks for an irreversible cleanup.
3. Create a self-contained prototype under `mobile/prototypes/` when visual comparison will reduce uncertainty. Prototype the narrow mobile viewport first and make theme alternatives switchable when palette selection is still open.
4. Translate the selected direction into semantic Material 3 roles and `ThemeExtension` tokens before editing page widgets. Keep colors, spacing, typography, shape, elevation, motion, and state feedback centralized.
5. Preserve the product's information architecture and permissions. Visual polish must not hide loading, empty, error, forbidden, saving, conflict, or offline states.
6. Use card, illustration, badge, and animation density deliberately. A warm cartoon treatment supports explanation and feedback; it must not turn business lists, approvals, or logs into a game screen.
7. Reuse existing components only when their visual contract matches the approved direction. When replacing them, migrate callers before removing the old package or assets.
8. Check accessibility: 48dp touch targets, readable contrast, text scaling, semantic labels, non-color status cues, and reduced-motion behavior.
9. Keep local assets with source, license, version, and attribution records. Never hotlink competitor assets or copy screenshots into production.
10. Perform one unified visual and Flutter verification pass after the approved implementation batch. During design exploration, use only focused checks and prototype screenshots.

## Prototype requirements

- The prototype must be runnable without a build tool when possible.
- Use real Chinese copy and representative empty/error/loading states, not only decorative placeholder text.
- Include the five product navigation entries: 导图、视图、日志、AI 地图、我的.
- Show the primary task, secondary actions, responsive behavior, and at least one state transition.
- Record the selected reference direction and the reasons for rejecting alternatives in a document under `mobile/docs/`.

## Project defaults

- Flutter target: Material 3, phone portrait first.
- Product type: enterprise collaboration workspace.
- Visual intent: friendly cartoon warmth with professional information hierarchy.
- Backend and AI behavior remain outside visual prototypes; mock or fixed data must be labeled.
- Do not introduce a new UI framework only for decoration. Prefer existing Flutter primitives and project components unless the approved design requires a real migration.
