## ADDED Requirements

### Requirement: 可连续演示的移动端 UI
The application SHALL order navigation as 导图、视图、日志、AI地图、我的 and preserve demo business data across role changes.

#### Scenario: Complete a task demonstration
- **WHEN** a manager dispatches a task and switches to its employee owner
- **THEN** the employee can receive and submit feedback and the manager can accept and archive the same task

### Requirement: 业务页面完整展示
The application SHALL display saved form content, related notification targets, member-specific panels, calendar periods, review steps, AI suggestions, analytics and help feedback using local demo data.

#### Scenario: Edit and inspect
- **WHEN** the user edits an existing record or confirms an AI suggestion
- **THEN** the form is prefilled and the resulting record and associated views reflect the submitted content
