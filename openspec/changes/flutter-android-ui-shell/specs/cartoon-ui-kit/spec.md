# 卡通风格 UI 包

## ADDED Requirements

### Requirement: 统一视觉令牌
The UI kit SHALL expose theme tokens for background, mint, coral, text, border, radius, elevation, typography, and spacing through Material 3 extensions.

#### Scenario: Render a feature page
- **WHEN** any feature page is rendered
- **THEN** its cards, buttons, labels, and empty states use the shared tokens rather than feature-local color literals

### Requirement: 本地素材与署名
The UI kit SHALL load cartoon icons from local assets and SHALL include the OpenMoji CC BY-SA 4.0 attribution record.

#### Scenario: Build without network
- **WHEN** the application is built in an environment without network access
- **THEN** all referenced illustrations and icons still render from bundled assets
