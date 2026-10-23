## ADDED Requirements

### Requirement: Scoped diary contract
The client SHALL preserve department, search, date and owner filters across all pages and retain server supplied author, department and edit capabilities.

#### Scenario: Next page
- **WHEN** a manager reads multiple pages with department and search filters
- **THEN** every request carries the same filters and only the cursor changes

#### Scenario: Expired withdrawn diary
- **WHEN** a diary retains a first submission deadline at or before the current time
- **THEN** the client does not offer editing even if the diary is now a draft

### Requirement: Comment replies
The client SHALL send parentId for replies, preserve reply identity on reads and MUST NOT automatically replay comment writes.

#### Scenario: Reply from HCJ
- **WHEN** the caller supplies parentCommentId
- **THEN** the HTTP body uses parentId and the response preserves the comment ID and author

#### Scenario: Failed comment write
- **WHEN** a comment POST times out or is rejected
- **THEN** the client reports the failure without retrying or claiming publication

### Requirement: Honest capability boundary
The client MUST reject unsupported modern task fields without dropping them or creating a legacy task, and SHALL retain review based diary revision semantics.

#### Scenario: Unsupported task payload
- **WHEN** a request supplies startAt, participantIds or tagId before backend support
- **THEN** it fails explicitly before any task POST
