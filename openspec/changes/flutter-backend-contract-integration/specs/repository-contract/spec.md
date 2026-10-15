# Repository Contract

## ADDED Requirements

### Requirement: Real mode uses backend routes
The mobile client SHALL use the backend Controller routes and HTTP verbs when `USE_MOCK=false`.

#### Scenario: Task list
- WHEN the task list is loaded in real mode
- THEN the client requests `GET /api/tasks` with backend query names and maps the response into `PageResult`.

#### Scenario: Task event
- WHEN a task lifecycle action is submitted in real mode
- THEN the client requests `POST /api/tasks/{id}/events` with the backend event type and current version.

### Requirement: Response normalization
The HTTP repository SHALL normalize backend snake_case fields and nested `body` values without changing page-layer models.

#### Scenario: Log response
- WHEN the backend returns `owner_id`, `business_date`, and nested `body`
- THEN the page receives a `Record` with owner, business date, and body fields available.

### Requirement: No fake success for missing APIs
The mobile client SHALL return an explicit unavailable failure when the backend has no corresponding endpoint.

#### Scenario: Feedback submission
- WHEN a feedback form is submitted and no backend feedback endpoint exists
- THEN the client shows an unavailable error and does not report a successful save.
