## ADDED Requirements

### Requirement: Relationship based graph hierarchy
The client SHALL arrange authorized map nodes by actual directed dependencies, expose type and source/action context, and provide an equivalent filtered reading list. Priority P1, original section5.4, existing client contracts only.

#### Scenario: Branched and disconnected map
- **WHEN** the service returns valid goals, other nodes and directed relations
- **THEN** dependencies SHALL determine top-to-bottom levels, goals SHALL be centered within rows, disconnected nodes SHALL be identified without invented edges, and all nodes SHALL remain reachable through pan and the list

#### Scenario: Cyclic or large graph
- **WHEN** actual edges contain a cycle or up to100 nodes are present with large text
- **THEN** cyclic nodes SHALL be explicitly identified without fictitious dependency order, geometry SHALL remain finite and nonoverlapping, and the canvas SHALL NOT truncate later levels

#### Scenario: Filter and source action
- **WHEN** the user searches or filters nodes and opens a node
- **THEN** diagram and reading list SHALL share the same nodes/visible edges, no match SHALL offer clear recovery, and actual source links and applicable existing sourced actions SHALL be readable without creating tasks on view

#### Scenario: Invalid or forbidden node
- **WHEN** node IDs/body/type/title are invalid or access to a source is denied
- **THEN** the client SHALL show an explicit recoverable error or clear protected content under existing access rules instead of rendering guessed data

### Requirement: Complete contextual member workspaces
Member workspaces SHALL preserve approved identity/category hierarchy and read every authorized page with the original owner and date scope. Overview SHALL preview at most3 records per category with a link to complete records. Member log dates SHALL be independent of calendar/report/diary dates and preserve validated dates carried from subordinate logs. Public diary rows SHALL require positive submitted evidence.

#### Scenario: A manager opens a member from a dated diary
- **WHEN** a manager follows a member link carrying a valid business date
- **THEN** the member log category SHALL use that date and owner across all pages and SHALL support clearing the filter without changing calendar/report/diary state

#### Scenario: More than30 records are authorized
- **WHEN** member records span multiple pages
- **THEN** overview SHALL expose accurate totals and compact previews and the corresponding category SHALL make the last record and detail available

#### Scenario: Member scope becomes inaccessible
- **WHEN** member identity or a visible category returns403 including on a later page
- **THEN** the client SHALL remove the member identity and protected body and offer retry or safe return without treating the result as empty or partial success

#### Scenario: Invalid route or unconfirmed diary
- **WHEN** a member category/date is invalid or a diary lacks positive submitted evidence
- **THEN** the client SHALL reject invalid routing before scoped reads and SHALL NOT display draft or unknown diary bodies in a public workspace

### Requirement: Truthful searchable help
Help and guide SHALL describe supported local saving/submit and actual task/AI behavior, distinguishing explicitly unsupported task returns or support contracts. Search with zero matches SHALL provide an empty result and clear-search action.

#### Scenario: An employee searches for an unknown topic
- **WHEN** no help article matches
- **THEN** the client SHALL show no-match feedback and a usable clear-search action while preserving guide and supported assistance entries


### Requirement: Complete scoped calendar and report reads
Calendar, diary history and period reports SHALL traverse existing server pagination while preserving authorization owner, search and date/period query. Shanghai business dates SHALL be derived independently of device timezone. Invalid/repeating/incomplete pagination or permission failures SHALL render explicit failure rather than a complete partial list. Reports SHALL aggregate submitted diaries only and distinguish draft counts and missing past calendar dates.

#### Scenario: A month contains more than one page
- **WHEN**31 source records or calendar events span multiple server pages
- **THEN** the client SHALL show the last record with the same original scope and date query and SHALL offer its actual detail entry

#### Scenario: Pagination or scope fails
- **WHEN** a cursor repeats, an incomplete page is empty, or a later request returns403
- **THEN** the client SHALL display a recoverable failure or forbidden state and SHALL NOT report partial rows as complete sources or empty data

### Requirement: Calendar sticky context and retained position
The week calendar SHALL retain dates and untimed/deadline rows above the scrolling24hour timeline. Sticky header and grid SHALL share horizontal position. Day strip SHALL expose selected date semantics, and switching away and back SHALL preserve scroll/date/mode. Buttons/body SHALL use the original readable type scale and remain reachable with large text.

#### Scenario: An employee scrolls to working hours
- **WHEN** the employee views or vertically scrolls a week timeline
- **THEN** week dates and untimed entries SHALL stay visible while time columns remain aligned and existing event detail actions remain available

#### Scenario: A period switch returns
- **WHEN** a user switches day/week/month and returns to a previously viewed date/mode
- **THEN** the selected date and retained timeline position SHALL be restored without changing report or diary dates

### Requirement: Approved sunny paper component states
The client SHALL use the original stage2 semantic Material3 roles and a SunnyPaperTokens ThemeExtension supporting copyWith and real interpolation. Primary buttons SHALL preserve the approved52dp target,18dp radius and3dp lower edge, press down2dp, visibly indicate focus and disable activation while disabled or loading. Loading SHALL retain its label and allocated width; reduced-motion preference SHALL remove press animation.

#### Scenario: An employee presses or focuses an action
- **WHEN** an enabled primary action is pressed or keyboard-focused
- **THEN** the button SHALL show the lower-edge press state or focus ring and SHALL retain Material keyboard/semantic activation

#### Scenario: An action is busy or forbidden
- **WHEN** a primary action is loading or disabled
- **THEN** it SHALL NOT invoke its callback and SHALL show progress or disabled colors without a raised edge rather than relying only on opacity

### Requirement: Business-aligned companion poses
The client SHALL provide original welcome,writing,explaining,success,empty and retry poses and wire them to corresponding business contexts, excluding decoration from semantics. Forbidden/pending/rejected states SHALL NOT celebrate. Calendar type filters SHALL expose their toggled state.

#### Scenario: A save completes
- **WHEN** a real local save or command succeeds
- **THEN** success feedback SHALL accompany truthful confirmation; pending revision feedback SHALL continue stating awaiting review

#### Scenario: Content is empty or cannot be read
- **WHEN** an empty list, network retry or permission failure renders
- **THEN** it SHALL present the matching empty/retry pose or neutral permission icon and a readable reason/recovery path without fabricated records

### Requirement: Reference-driven main screens
The mobile client SHALL rebuild the five main screens using the approved eight-screen reference and SHALL preserve 导图、视图、日志、AI地图、我的 navigation order with 导图 as default. Priority is P1; scope is mobile UI only.

#### Scenario: Employee opens the workspace
- **WHEN** an active employee opens each main screen
- **THEN** dashboard SHALL use four compact summary tiles and a today-view entry, calendar SHALL use period pills and date agenda, logs SHALL use period browsing and date rows with a fixed write action, AI SHALL prioritize numbered recommendations with sources, and profile SHALL group identity, metrics and plain work rows

#### Scenario: Data is empty or inaccessible
- **WHEN** loading fails, data is empty, or permission is missing
- **THEN** the screen SHALL show the corresponding state without inventing records, drafts or AI recommendations

### Requirement: Purpose-specific detail and editor layouts
The client SHALL use a continuous document for diary editing, attributes plus an event timeline for task details, and effective/candidate comparison for review details. Primary actions SHALL remain outside the scrollable body. Priority is P1.

#### Scenario: User saves and submits a diary
- **WHEN** the user enters diary content and saves a draft
- **THEN** content SHALL be persisted under the account and business date and its actual save time SHALL be displayed independently of calendar filters

#### Scenario: Submission fails
- **WHEN** submission fails or hours are outside zero to twenty-four
- **THEN** input SHALL remain available and the user SHALL receive a clear error with separate save and retry actions

#### Scenario: User acts on a task
- **WHEN** a task detail is opened
- **THEN** its permitted main action SHALL appear at the bottom and secondary management actions SHALL be in a More menu; the dispatch list and form SHALL NOT display completion fields or status substitutes

#### Scenario: Applicant opens their review
- **WHEN** the review applicant opens the review or a reviewer rejects it
- **THEN** self-approval SHALL be unavailable, rejection SHALL require a reason, and the old version SHALL remain effective until independent review finishes

### Requirement: Supporting documents and action context
The supporting pages SHALL retain the original section 6 contracts: actual current values before task changes, results before acceptance, read-only historical diary documents, own profile focus and diary timeline, and own private notes separated from public content. Priority is P1; scope excludes new backend contracts.

#### Scenario: User inspects a related document
- **WHEN** a user opens acceptance, a task change, profile, or a historical diary
- **THEN** the client SHALL display authorized existing content in a reading section before editable controls or chronological rows, without inventing missing values

#### Scenario: Permission or an action fails
- **WHEN** access is refused, a historical document is missing, or a primary action fails
- **THEN** private data SHALL be hidden, a safe recovery path SHALL remain available, and fixed-action failures SHALL be visible near the primary action rather than below a long document

### Requirement: Evidence-based visual acceptance
The implementation MUST provide eight actual Flutter-rendered screenshots and document comparison against both approved reference boards. Priority is P1; verification covers UI behavior and does not substitute for backend acceptance.

#### Scenario: Unified acceptance runs
- **WHEN** the implementation batch is complete
- **THEN** analysis, tests, Flutter test compilation (APK builds are excluded by user instruction), visual comparison, small-screen and enlarged-text checks SHALL run with recorded commands and explicit results before corresponding tasks are checked

#### Scenario: Verification environment is incomplete
- **WHEN** device, backend or remote workflow evidence cannot be obtained
- **THEN** the missing evidence SHALL be recorded as unverified and SHALL NOT be represented as completed production functionality

### Requirement: Existing-contract supporting page adapters
The client SHALL use existing private-note and profile contracts without fabricating successful identity edits or treating a display key as a server object ID. Priority is P1; scope is client mapping only.

#### Scenario: Own note is read and saved
- **WHEN** a user reads a note associated with a visible company item or task and saves it
- **THEN** the client SHALL match resource, object ID and owner from the returned own records, display text, and send resource, objectId, text and the actual note version (zero for creation) to the existing PUT endpoint

#### Scenario: A note is missing or a target is invalid
- **WHEN** no own note exists, a supplied key is malformed, or a target is unsupported by the server
- **THEN** only an absent supported note SHALL allow new-note editing; invalid or unsupported targets SHALL fail explicitly before issuing a save request, and forbidden/network/conflict failures SHALL preserve input without claiming success

#### Scenario: Profile introduction is updated
- **WHEN** the user edits the actual introduction returned inside the profile object
- **THEN** the client SHALL preserve the existing avatar attachment ID and profile version, keep name and organization identity read-only according to the product baseline, and refresh from the successful response

#### Scenario: A selected local avatar is not uploaded
- **WHEN** only a local file name is available
- **THEN** it SHALL NOT replace an existing server avatar reference or be presented as an uploaded avatar

### Requirement: Existing-object commands and candidate semantics
The client SHALL route commands to their original object identity, convert asynchronous HTTP failures into typed UI errors, and preserve existing draft versions. Priority is P1; scope is existing client adapters.

#### Scenario: A user changes an existing record
- **WHEN** a permitted task, diary, comment, review, focus or notification mutation is sent
- **THEN** the client SHALL retain its original object ID in the existing URL or allowed payload fields and SHALL present403/409 as recoverable typed failures

#### Scenario: A task owner or deadline is changed
- **WHEN** a dispatcher requests transfer or reschedule
- **THEN** the client SHALL submit a full candidate to the existing task revision endpoint, preserving authorized current task fields and requiring reason/version; the current effective version SHALL NOT be changed immediately

#### Scenario: Invalid identity or unsupported return is submitted
- **WHEN** a command requiring an existing ID has none, the task version is stale, or return-to-supplement has no existing service contract
- **THEN** the client SHALL fail explicitly and SHALL NOT issue a mutation using an empty/null path or a different event type

#### Scenario: A new diary is submitted
- **WHEN** a new draft is saved successfully and then submitted
- **THEN** the submit request SHALL use the ID and version returned by the draft write rather than a hardcoded version

### Requirement: Existing read contracts and scoped recovery
The client SHALL connect the existing focus lists, diary historical versions/comments, task lifecycle events and notification fields to the approved reading layouts. Priority is P1; scope is client read mapping without new API.

#### Scenario: A visible focus is opened
- **WHEN** a user opens company focus or a member's personal focus
- **THEN** the client SHALL resolve the requested ID from existing authorized paged lists and retain the explicit owner context for member focus rather than calling a nonexistent single-object endpoint

#### Scenario: Focus is inaccessible or absent
- **WHEN** the scoped read is forbidden or paging is exhausted without the requested ID
- **THEN** the client SHALL show typed access/not-found recovery and SHALL NOT substitute another member's or the first record's content

#### Scenario: Submitted diary history and comments are read
- **WHEN** a submitted diary is opened
- **THEN** the client SHALL read actual version bodies and comments from existing endpoints, render requested historical content independently of current body, and use real returned metadata

#### Scenario: An auxiliary diary read fails
- **WHEN** history/comments fail due to network or server errors, or access is denied
- **THEN** network failures SHALL retain main context with inline recovery rather than empty-data claims, while401/403 SHALL clear protected content and show safe recovery

#### Scenario: Task detail has lifecycle events without phase
- **WHEN** actual events contain lifecycle transitions including an approved REVISED event
- **THEN** the client SHALL derive the current applicable main action from ordered events, reset receive state for REVISED, and never invent an action from unknown-only events

#### Scenario: Notification has a known or unknown type
- **WHEN** server fields include is_read, recipient_id, type and object_id
- **THEN** read status SHALL reflect is_read and only known task/log/review types SHALL map to their real object routes; unknown types SHALL remain readable without guessed targets

### Requirement: Authentication layouts follow actual session states
The client SHALL implement the original authentication layouts using actual login and auth/me state without exposing business content before activation or mandatory password change. Priority is P0; scope is existing client auth contracts.

#### Scenario: Pending or mandatory-change user opens a business link
- **WHEN** login returns PENDING or must_change_password, or the user opens a business deep link in that state
- **THEN** the client SHALL show only pending refresh/exit or required password editing and SHALL NOT read business data

#### Scenario: Pending account status is refreshed
- **WHEN** the authenticated pending user requests refresh
- **THEN** the client SHALL call existing auth/me and enter business only after ACTIVE and no mandatory password requirement; failure SHALL retain status with retry

#### Scenario: Credentials or a session request fail
- **WHEN** INVALID_CREDENTIALS, ordinary object403, protected session401, or explicit account-state403 is returned
- **THEN** invalid credentials SHALL retain the form, ordinary403 SHALL remain local, and only session/account-state failures SHALL clear or restrict business access; obsolete-token failures SHALL NOT expire a new session

#### Scenario: User changes password or logs out
- **WHEN** existing password API confirms revocation or logout API succeeds
- **THEN** the old token and protected navigation SHALL be cleared, relogin SHALL be required, and per-account local diary drafts SHALL remain isolated and retained

#### Scenario: Logout fails or the app resumes
- **WHEN** logout fails due to networking, or an authenticated app resumes
- **THEN** failed logout SHALL offer retry without claiming remote revocation, and resume SHALL validate auth/me behind a safe checking/recovery screen before displaying business content

#### Scenario: Credentials cannot be restored safely
- **WHEN** the process restarts without a secure credential store
- **THEN** the client SHALL require login rather than persist tokens in ordinary preferences or claim persistent session recovery

### Requirement: Existing management and analytics contracts drive their layouts
The client SHALL use existing authorized organization, candidate revision, audit and analytics contracts for original section6.4 pages. Priority is P1; scope is client mapping and layouts only.

#### Scenario: Manager reads statistics and exports
- **WHEN** a manager selects a business date/period and opens analytics or exports logs/tasks
- **THEN** summary SHALL use the actual server object metrics, denominators, definitions, distribution and timestamp, and export SHALL use the same date/period and preserve received CSV bytes in an explicit save operation

#### Scenario: Summary fails, denominator is zero or saving is canceled
- **WHEN** analytics is forbidden/unavailable, a denominator is zero, or saving is canceled/fails
- **THEN** protected results SHALL be cleared, zero denominator SHALL be unavailable rather than a meaningful rate, and canceled/failed export SHALL NOT claim a saved file

#### Scenario: Authorized organization is browsed
- **WHEN** a manager reads departments, teams and members or selects a member for change
- **THEN** the client SHALL retain actual organization IDs/names including empty units, page visible people safely, and read current member public profile/version before editing

#### Scenario: Administrator submits a configuration change
- **WHEN** department/team/user or review policy changes are requested
- **THEN** only allowed existing candidate fields, actual version and required reason SHALL be submitted and the UI SHALL explain that current effective data remains until independent review

#### Scenario: Input is invalid, stale or unauthorized
- **WHEN** target/team/role fields are invalid, version conflicts or permission disappears
- **THEN** no malformed mutation SHALL be sent, conflict SHALL retain inputs with explicit reload, and forbidden reads SHALL hide current data and disable submit

#### Scenario: Audit or rejected review is opened
- **WHEN** an audit ID is read or a rejected management change is revisited
- **THEN** audit SHALL resolve from authorized paging and display actual event metadata/before/after, and management review SHALL NOT route into a company-content edit form

### Requirement: Existing controlled attachment and assignment flows drive the UI
The client SHALL implement original task attachments, member assignment and avatar presentation with existing protected server contracts. Priority is P1; scope is Flutter Repository and dedicated UI only.

#### Scenario: A dispatcher chooses files and collaborators
- **WHEN** authorized active people and valid files are selected
- **THEN** uploads SHALL use multipart file and creation SHALL use successful server attachment IDs and unique actual collaborator IDs, with single primary owner and no owner duplication

#### Scenario: File selection or upload is invalid, canceled or fails
- **WHEN** size is outside1byte..10MB, picker cancels, upload is pending/fails, or its response lacks an ID
- **THEN** no malformed upload or task mutation SHALL occur, inputs SHALL remain recoverable, pending submission SHALL be disabled and explicit retry/removal SHALL be available

#### Scenario: Editor closes or account changes during an upload
- **WHEN** selected/uploading content belongs to a disposed editor or previous account
- **THEN** it SHALL be canceled/discarded and its late response SHALL NOT enter another account's editor or task

#### Scenario: A user downloads a task attachment
- **WHEN** GET /attachments/{id} authorizes the request and system saving succeeds
- **THEN** exact bytes SHALL be saved using a sanitized server filename and the UI SHALL report successful saving only after the returned saved location

#### Scenario: Attachment access or saving fails
- **WHEN** download is forbidden/missing, saving fails or is canceled
- **THEN** protected content SHALL not be retained or substituted, retry SHALL be explicit and no saved-file success SHALL be reported

#### Scenario: Own avatar is replaced
- **WHEN** a valid PNG/JPEG/WebP image upload succeeds and the profile is saved
- **THEN** profile SHALL preserve introduction/current version, send the actual new avatar ID and display authenticated bytes; failure SHALL retain the original avatar and image-decode failure SHALL have a safe fallback

#### Scenario: Existing feedback contract cannot attach a file
- **WHEN** a task feedback or support form is opened and no supported attachment association exists
- **THEN** the UI SHALL explain the missing association, SHALL NOT upload an orphan file as if attached and SHALL preserve supported feedback and blocker text

#### Scenario: People search has more than one page
- **WHEN** a dispatcher searches names or departments and loads more candidates
- **THEN** the picker SHALL pass search/cursor/dispatch=true to the existing authorized endpoint, retain selection and avoid showing pending/disabled users as valid assignment targets

### Requirement: Formal AI pages use actual sourced jobs and human confirmation
The client SHALL implement original AI layouts using authenticated existing server AI contracts only. Priority is P2; scope is Flutter typed mapping, state and UI without server or schema change.

#### Scenario: A user generates analysis
- **WHEN** an authorized user selects a date and period and requests a summary or a source-specific purpose
- **THEN** the client SHALL send only supported input fields, display actual job state and consume SSE without presenting partial JSON as completed suggestions, then GET the authoritative final job

#### Scenario: Streaming ends or AI service fails
- **WHEN** streaming disconnects, job fails, service is unconfigured, or budget/rate limit is reached
- **THEN** input and previously completed output SHALL remain recoverable, actual error SHALL be visible and explicit refresh/retry SHALL NOT be an automatic new charged generation

#### Scenario: Cancellation or account replacement occurs
- **WHEN** the user cancels a running job, or page/account changes during a request
- **THEN** cancellation SHALL use the existing server DELETE only for explicit user cancellation, disposed transport SHALL close, and old account responses SHALL NOT populate the new account

#### Scenario: Sources are missing, mismatched or forbidden
- **WHEN** an output reference cannot be resolved to a matching allowed input/source route or source access is rejected
- **THEN** no arbitrary external navigation or task confirmation SHALL occur and protected results SHALL be cleared on forbidden/unauthorized job reads

#### Scenario: A user edits a completed draft
- **WHEN** editable summary/actions and original references are saved
- **THEN** PUT SHALL preserve source/node contracts and actual version;409 SHALL retain input and require explicit confirmed reload before replacing it

#### Scenario: A dispatcher confirms an action
- **WHEN** an authorized dispatcher chooses an actual active owner, future deadline and complete editable task for a sourced action
- **THEN** only explicit human confirmation SHALL POST the existing job confirmation endpoint with actual actionIndex, task and stable Idempotency-Key after re-reading the job; ordinary viewing/editing SHALL NOT create a task

#### Scenario: A map or usage screen opens
- **WHEN** the user reads nodes/edges or usage and adds a valid dependency
- **THEN** only actual authorized server data SHALL be displayed, map SHALL provide zoom and a list alternative, edge SHALL use actual distinct node IDs and usage SHALL NOT invent metrics

#### Scenario: Scope narrowing is unsupported
- **WHEN** a formal AI page renders current scope
- **THEN** it SHALL state the actual actor-authorized data scope and SHALL NOT present a scope switch that the existing API cannot enforce

### Requirement: Complete safe inboxes and real diary comparison
The client SHALL implement original common inbox/synchronization layouts using existing authenticated contracts and encrypted drafts. Priority P1, scope client only.

#### Scenario: A record is beyond the first page
- **WHEN** scoped task/review/notification/audit records exceed30
- **THEN** search/filter/count SHALL include all authorized pages without partial success

#### Scenario: Pagination breaks or access is revoked
- **WHEN** cursor/total/records are inconsistent or a later page returns403
- **THEN** a typed failure SHALL replace protected rows including during refresh, while retaining filters and safe recovery

#### Scenario: A user marks messages read
- **WHEN** individual read/read-all runs, fails, or completes after account/token replacement
- **THEN** repeated actions SHALL be disabled, failure SHALL preserve unread/error, and stale completion SHALL NOT refresh/navigate the replacement session

#### Scenario: A message target is unavailable
- **WHEN** target is unknown/missing or deleted
- **THEN** only known internal targets SHALL navigate and unavailable content SHALL explain safe return

#### Scenario: A user checks a diary version
- **WHEN** a valid active account/day or own revision id/version is selected
- **THEN** actual encrypted local and scoped server detail SHALL show saved time/version and paired sections without draft replacement/submission

#### Scenario: Sync identity or route is invalid
- **WHEN** date/version is invalid, returned owner/day mismatches, or session/access changes
- **THEN** invalid routes SHALL perform zero reads, protected content SHALL be hidden, and old-session responses SHALL be discarded

#### Scenario: A user rechecks or returns to editing
- **WHEN** recheck or continue-edit is explicit
- **THEN** recheck SHALL NOT mutate draft/server, date SHALL remain independent, and editor SHALL retain original draft version and explicit conflict replacement confirmation

### Requirement: Session-scoped live notifications and strict contextual reads
The client SHALL consume existing authorized notification SSE with authoritative GET refresh and SHALL reject partial contextual reads. Priority P1, client only.

#### Scenario: New or replayed notification arrives
- **WHEN** a valid positive matching SSE id/sequence exceeds the current session cursor
- **THEN** the client SHALL debounce authoritative list refresh without storing/displaying streamed protected bodies or creating business commands; duplicates SHALL NOT refresh

#### Scenario: Streaming disconnects or framing is invalid
- **WHEN** transport closes/fails transiently or frame/header/id is invalid
- **THEN** same-session reconnect SHALL retain Last-Event-ID with bounded backoff and explicit retry after five failures, while malformed/forbidden streams SHALL stop and explain recovery without claiming live updates

#### Scenario: Session or app lifecycle changes
- **WHEN** app backgrounds, identity validation starts, account/token/access changes, or app disposes
- **THEN** old transport/subscription/timers SHALL stop, old responses SHALL NOT refresh the next session, and resumed transport SHALL wait for confirmed identity

#### Scenario: Contextual records exceed one page
- **WHEN** organization people or focused/audit detail lookup spans31 or more records
- **THEN** the client SHALL retain scope/owner and read all valid pages before exposing tree/count or concluding a detail is absent

#### Scenario: Contextual pagination is incomplete or forbidden
- **WHEN** a later page has invalid cursor/count/duplicates or403
- **THEN** the UI SHALL clear protected tree/detail and show the actual failure instead of partial success or false nonexistent

### Requirement: Lossless multiple diary task associations
The client SHALL preserve all existing diary taskIds through document editing, encrypted drafts, revisions and scoped reading. Priority P0, existing client/API only.

#### Scenario: A diary has multiple task associations
- **WHEN** a diary with two or more taskIds is read, restored, saved or revised
- **THEN** all distinct IDs SHALL remain ordered and SHALL be sent as taskIds without replacing IDs with displayed titles or keeping only the first

#### Scenario: A user selects tasks
- **WHEN** authorized tasks are searched across complete pages, selected, filtered, canceled or explicitly confirmed
- **THEN** multiple selections SHALL persist across search, cancel SHALL NOT modify the document, confirmation SHALL update chips, and each association SHALL support explicit removal

#### Scenario: A linked task is unavailable or loading fails
- **WHEN** a linked task is absent from the authorized list, a later page fails, or authorization is lost
- **THEN** existing IDs SHALL NOT be silently removed, protected titles SHALL be hidden on failure, and only accessible records SHALL provide navigation

#### Scenario: A picker outlives its account
- **WHEN** account/token/access changes while selection is open or a result is pending
- **THEN** protected rows SHALL disappear and the old selection SHALL NOT modify the replacement session or original document

#### Scenario: Association data is invalid or legacy
- **WHEN** legacy singleton draft data, duplicate valid IDs, or malformed/non-string list input is encountered
- **THEN** legacy values SHALL remain readable, duplicates SHALL be normalized without reordering, and malformed input SHALL show explicit failure without replacing stored associations

### Requirement: Explicit submitted diary reading receipt
The client SHALL acknowledge reading through the existing service only on explicit action and SHALL distinguish unknown reading-list data from empty records. Priority P1, client only.

#### Scenario: A submitted diary is read
- **WHEN** an authorized active user explicitly records reading
- **THEN** the client SHALL post an empty object to the exact diary read endpoint, block duplicate pending actions and show acknowledgement only after ok=true without changing body or version

#### Scenario: Reading acknowledgement fails
- **WHEN** response is malformed, network fails or the service returns401/403
- **THEN** the client SHALL show failure and allow appropriate explicit recovery, while access failures SHALL remove protected document content

#### Scenario: Reading response outlives its context
- **WHEN** account/token/access, route or widget lifecycle changes before completion
- **THEN** stale acknowledgement SHALL NOT publish confirmation, refresh or navigate another context

#### Scenario: A draft or historical document is opened
- **WHEN** a draft, unknown submission state, detail GET or historical version is loaded/rebuilt
- **THEN** no implicit read write SHALL occur and drafts SHALL NOT expose a reading action

#### Scenario: Reading-list data is unavailable
- **WHEN** the actual response omits read-list data
- **THEN** the UI SHALL explain unavailability instead of claiming no one has read, and an actual submitted timestamp SHALL be displayed when provided
