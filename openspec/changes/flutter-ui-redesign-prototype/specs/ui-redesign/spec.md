## ADDED Requirements

### Requirement: Purpose-specific page layouts
The mobile UI SHALL use a two-by-two dashboard, a seven-column mobile month calendar with selected-day agenda, document-oriented log reading/editing, and grouped personal work entries. Task dispatch lists and forms MUST NOT display completion or substitute status fields or filters.

#### Scenario: Employee selects a calendar date
- **WHEN** an employee selects a date in the month grid and opens an event
- **THEN** the agenda presents readable full event titles and returning preserves the selected date without changing the log filter date.

#### Scenario: Employee submits an invalid log or request fails
- **WHEN** required content is missing, hours are invalid, or submission fails
- **THEN** the editor preserves input and explains correction or retry; submission uses the editor's business date and does not use the calendar selection.

### Requirement: Member context and review reading
The UI SHALL make the viewed member explicit and provide category navigation without exposing private notes or unsubmitted drafts. Review detail SHALL distinguish current effective content from the candidate change and preserve independent review requirements.

#### Scenario: Manager reads a member or review
- **WHEN** an authorized manager opens a member workspace or pending revision
- **THEN** the member context or effective/candidate versions are visible and only authorized operations are available.

#### Scenario: Access is denied
- **WHEN** the repository rejects access
- **THEN** the UI displays refusal and recovery without sample success or protected cached content.

### Requirement: Confirmed anime orange sunny paper theme
The mobile UI SHALL use the confirmed 阳光纸张 theme with vivid anime orange primary actions, cream surfaces, soft rounded components and a coherent original chibi work companion. Theme roles SHALL be centralized in Material 3 and ThemeExtension tokens.

#### Scenario: Main theme is displayed
- **WHEN** the user opens an implemented main page
- **THEN** primary actions use #FF8A24 with the paired dark foreground, and card/button/input shapes follow the stage-2 specification rather than legacy mint or muted brown-orange rules.

#### Scenario: Small text and active controls
- **WHEN** text or a focused interactive control appears on a theme surface
- **THEN** ordinary text has at least 4.5:1 contrast and necessary control boundaries at least 3:1; white ordinary button text on the vivid primary orange is rejected.

### Requirement: Chibi companion expresses real state
The UI SHALL use an original or appropriately licensed chibi companion consistently for welcome, writing, source explanation, empty, retry and confirmed-success states. Decorative characters MUST NOT obscure input, identify a real reviewer or imply a business result that has not occurred.

#### Scenario: Confirmed business success
- **WHEN** saving or submitting actually succeeds
- **THEN** the UI may show one brief positive character response and accurate text.

#### Scenario: Failure or pending review
- **WHEN** a request fails, is offline, lacks permission or awaits review
- **THEN** the UI shows the actual state and recovery path without success celebration or fabricated records.

### Requirement: Prototype preserves product structure
The replacement prototype SHALL preview the single confirmed theme with five navigation entries ordered 导图、视图、日志、AI地图、我的 and default 导图. It SHALL preserve the two-by-two company focus/company tasks/personal focus/personal logs structure, preview an editable form and demonstrate at least one failure recovery. Mock content SHALL be visibly identified.

#### Scenario: User opens and navigates the prototype
- **WHEN** the user opens the replacement prototype and selects a main entry
- **THEN** the content and selected navigation agree, and the workbench has all four product areas.

#### Scenario: User encounters a failed form operation
- **WHEN** a demonstration submission fails
- **THEN** entered content remains visible and retry is available; a toast alone does not count as a completed workflow.

### Requirement: Accessible rounded components
Interactive targets SHALL be at least 48dp, support readable labels and non-color state cues. Components SHALL support text scaling and reduced motion while preserving navigation, actions and content.

#### Scenario: Narrow screen or enlarged text
- **WHEN** a page is shown at 360dp width or 1.5 times text scale
- **THEN** primary actions remain reachable, headings can wrap, and illustrations do not clip business information.

#### Scenario: Reduced motion enabled
- **WHEN** the system requests reduced motion
- **THEN** decorative character animation is static and transitions preserve immediate, readable state feedback.

### Requirement: Visual migration preserves authority and privacy
Theme migration MUST preserve server authorization, private draft/note boundaries and existing API contracts. Dispatch pages SHALL NOT add completion or substitute status fields, subordinate logs SHALL retain the log-page entry, and AI suggestions SHALL retain sources and explicit human confirmation.

#### Scenario: Employee or pending account opens protected content
- **WHEN** the server denies a protected request
- **THEN** the UI shows refusal without replacing it with success samples or exposing private data.

#### Scenario: AI recommendation is presented
- **WHEN** a recommendation is displayed
- **THEN** sources and uncertainty remain readable, and a character animation does not create or publish a formal task.

### Requirement: Old assets migrate before removal
The project SHALL remove legacy resources only after replacement callers are migrated and reference checks confirm they are unused. Character, font and animation assets SHALL have local source/license records, with OpenMoji CC BY-SA 4.0 attribution preserved.

#### Scenario: Legacy cleanup is performed
- **WHEN** unused assets are removed after the migration
- **THEN** no active caller depends on them, attribution remains for retained assets, and validation evidence is recorded.
