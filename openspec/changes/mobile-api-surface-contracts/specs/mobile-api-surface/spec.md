# mobile-api-surface Specification

## ADDED Requirements

### Requirement: Frontend operations have explicit service status
The mobile client and its integration documentation MUST identify each user-visible business operation as a supported remote API, a local-only operation, a demo-only operation, or a pending contract. A demo implementation MUST NOT be represented as a production API.

#### Scenario: Backend implementer looks up a screen operation
- WHEN a backend implementer uses the mobile API coverage matrix
- THEN the operation name, current/proposed path or pending-path state, request/response intent, permission owner, and known validation/concurrency requirements are visible
- AND a path not present in runtime OpenAPI is marked proposed or pending rather than implemented

#### Scenario: A screen action is demo-only
- WHEN an operation exists only in MockRepository or local storage
- THEN the matrix marks it demo-only or local-only
- AND the real adapter does not claim remote success

### Requirement: REST resource routing fails closed
The mobile HTTP adapter MUST issue list/detail requests only for explicitly registered resource routes. It MUST NOT construct a URL from an unknown resource string.

#### Scenario: An unknown list resource is requested
- WHEN the client requests a list for an unregistered resource
- THEN the adapter returns an explicit unavailable failure before making an HTTP request

#### Scenario: An unknown detail resource is requested
- WHEN the client requests a detail for an unregistered resource
- THEN the adapter returns an explicit unavailable failure before making an HTTP request

### Requirement: Draft and submitted log operations remain distinct
The mobile adapter MUST NOT route an edit of a submitted log to the endpoint that saves an unsubmitted draft.

#### Scenario: Submitted-log direct edit has no server contract
- WHEN the UI submits a direct edit operation for a submitted log
- THEN the adapter reports the operation as unavailable without calling the draft endpoint
- AND the original submitted record remains unchanged

### Requirement: Missing backend capabilities remain explicit
The mobile contract MUST preserve a tracked status and intended operation boundary for every identified production gap until a reviewed server contract and implementation are available.

#### Scenario: An unimplemented capability is displayed
- WHEN feedback, task return, task comments/replies, read roster, tag dictionary, AI scope selection, or atomic AI confirmation is not implemented by the server
- THEN the client reports it as pending/unavailable or demo-only
- AND it MUST NOT call an invented endpoint or report a successful production write
