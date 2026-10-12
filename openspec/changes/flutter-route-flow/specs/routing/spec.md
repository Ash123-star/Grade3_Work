# Routing

## ADDED Requirements

### Requirement: Main navigation routes
The Flutter client SHALL expose the five confirmed main navigation entries as `/dashboard`, `/view`, `/logs`, `/ai`, and `/me`, with `/dashboard` as the default authenticated location.

#### Scenario: Authenticated startup
- **WHEN** an active session starts the application
- **THEN** the router opens `/dashboard` and shows the five navigation entries in the approved order.

### Requirement: Management member workspace routes
The Flutter client SHALL expose a manager-only member workspace at `/me/team` and member category deep links under `/me/team/:memberId`.

#### Scenario: Manager opens a member category
- **WHEN** a manager opens `/me/team/:memberId/logs`
- **THEN** the router opens the selected member detail context without changing the bottom navigation order.

#### Scenario: Employee opens a protected route
- **WHEN** a non-manager opens the member workspace
- **THEN** the route is subject to the existing session and permission guard and does not expose a member workspace entry.

### Requirement: Authentication routes
The Flutter client SHALL use `/auth/login`, `/auth/register`, `/auth/password`, `/auth/pending`, `/auth/expired`, and `/auth/disabled` for authentication states.

#### Scenario: Session is inactive
- **WHEN** an unauthenticated user requests a protected route
- **THEN** the router redirects to `/auth/login`.
