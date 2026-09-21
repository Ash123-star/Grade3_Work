# Flutter Android 前端框架

## ADDED Requirements

### Requirement: 五栏导航与默认导图
The application SHALL provide five primary destinations ordered left-to-right as 我的、AI 地图、日志、视图、导图, and SHALL open 导图 on first entry.

#### Scenario: Open application
- **WHEN** a local demo user launches the application
- **THEN** the shell displays the five destinations and selects 导图 without requiring a backend response

### Requirement: 全页面可访问
The application SHALL provide non-empty routes for the dashboard, AI map, logs, calendar view, profile, task detail, task dispatch, approvals, notifications, settings, subordinate logs, and log history.

#### Scenario: Navigate through a feature
- **WHEN** the user taps a card, list item, action button, or notification
- **THEN** the application opens the related route or displays a clear unavailable state instead of a blank page

### Requirement: 导图四象限
The dashboard SHALL show company important items, company assigned tasks, personal important items, and personal logs as four sections, with compact previews and an expand action on small screens.

#### Scenario: View dashboard
- **WHEN** the dashboard loads with demo data
- **THEN** company sections are read-only, personal sections expose edit affordances, and private notes are visually marked as private

### Requirement: 权限状态预留
The client SHALL represent the current user role, data scope, and task-dispatch permission independently from widget visibility.

#### Scenario: User lacks dispatch permission
- **WHEN** the permission snapshot denies task dispatch
- **THEN** the floating dispatch action is absent and a direct repository call returns a typed permission failure

### Requirement: 卡通风格 UI
The application SHALL use the shared cute theme, local OpenMoji assets, accessible contrast, and touch targets of at least 48dp for primary actions.

#### Scenario: Empty or loading state
- **WHEN** a feature has no data or is waiting for a repository response
- **THEN** it displays a themed illustration and explanatory text without shifting the surrounding layout
