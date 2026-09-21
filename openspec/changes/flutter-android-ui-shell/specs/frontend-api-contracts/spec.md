# 前端接口契约

## ADDED Requirements

### Requirement: 可替换数据源
The client SHALL define repository interfaces and mock implementations for auth, organization, dashboard, tasks, logs, reviews, notifications, analytics, and AI maps.

#### Scenario: Replace mock with HTTP
- **WHEN** a feature changes from mock data to a Dio-backed repository
- **THEN** its widgets and controllers retain the same typed models and loading/error states

### Requirement: 统一错误与失败状态
The client SHALL map timeout, unauthorized, forbidden, validation, not-found, and server failures into typed errors that each page can render.

#### Scenario: API unavailable
- **WHEN** a repository returns a timeout or server failure
- **THEN** the page shows retry and fallback actions, and the navigation shell remains usable

### Requirement: AI 密钥隔离
The client SHALL never contain a DeepSeek API key and SHALL treat AI results as source-linked draft suggestions.

#### Scenario: Generate an AI suggestion
- **WHEN** the AI repository returns a suggestion
- **THEN** the UI shows source references, generated time, editable draft content, and an explicit confirmation action before any future task creation
