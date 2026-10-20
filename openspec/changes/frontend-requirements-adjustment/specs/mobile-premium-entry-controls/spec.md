# Spec Delta

## ADDED Requirements

### Requirement: Mobile task and log entry controls

The mobile task and log entry flows SHALL use app-owned rounded selection surfaces for tags, dates, times, and task-management filters. Tag options SHALL show the tag name inside a capsule filled with its tag color. Task management SHALL filter by tag, participant, and one user-selected local calendar date only; it SHALL NOT expose task status or urgency filters. Task creation SHALL NOT collect or submit urgency.

#### Scenario: Choose a tag
- **WHEN** a user opens the tag field
- **THEN** all supported mock tags appear as colored capsules, the selected tag is indicated, and cancel leaves the current value unchanged

#### Scenario: Choose task date and time
- **WHEN** a user opens a task start or deadline field
- **THEN** an app-owned calendar and a simple wheel time selector return the selected local date and minute, or leave the field unchanged when canceled

#### Scenario: Filter tasks
- **WHEN** a user filters task management
- **THEN** tag, participant, and a selected local calendar day can be applied together; clearing them restores all tasks, while status and urgency are absent

### Requirement: Compact public comment stream

Public comments SHALL use a compact social-feed layout with author avatar, name, timestamp, inline reply attribution, body, and a reply action while preserving empty-input validation and posting failure feedback.

#### Scenario: Reply and posting failure
- **WHEN** a user replies to a comment or comment submission fails
- **THEN** the parent attribution remains visible, empty comments are rejected, and the failure can be read and retried

### Requirement: Blank daily log creation

Pressing the log page create button SHALL open a blank daily-log form without loading existing entries or restoring a device draft. A separate continue-draft action MAY explicitly restore the local diary draft. The primary action on a new diary form SHALL read “提交”. Existing daily uniqueness and the 24-hour edit window SHALL remain enforced by the repository.

#### Scenario: Create an empty diary
- **WHEN** a user presses the create-log button
- **THEN** the form starts empty for the selected business date and does not copy an existing diary or local draft

#### Scenario: Continue a local draft
- **WHEN** a user presses the explicit continue-draft action
- **THEN** the local draft is restored into the diary form

#### Scenario: Duplicate daily submission
- **WHEN** an empty new diary is submitted for a date that already has a diary
- **THEN** the repository rejects the duplicate and the existing diary remains unchanged
