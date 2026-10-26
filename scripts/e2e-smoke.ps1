# E2E core-link regression against the real compose backend started by start-backend.ps1.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/e2e-smoke.ps1 [-BaseUrl ...] [-Admin admin] [-AdminPassword '...']
# Read-only + controlled writes to a real backend. No business code is modified.
# Output is ASCII only to stay legible under Windows PowerShell 5 (GBK console).
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080/api',
    [string]$Admin = 'admin',
    [string]$AdminPassword = 'Initial-local-2026!'
)
$ErrorActionPreference = 'Stop'
$script:tokens = @{}
$script:ids = @{}
$script:step = 0
$strongPassword = 'Workpanel-e2e-2026!'
$businessDate = (Get-Date).ToString('yyyy-MM-dd')

function Invoke-Api {
    param(
        [int]$Expect, [string]$Method, [string]$Path,
        [string]$Who = $null, $Body = $null, [string]$IdempotencyKey = $null
    )
    $headers = @{}
    if ($Who) { $headers['Authorization'] = "Bearer $($script:tokens[$Who])" }
    if ($IdempotencyKey) { $headers['Idempotency-Key'] = $IdempotencyKey }
    $reqArgs = @{ Uri = "$BaseUrl$Path"; Method = $Method; Headers = $headers; TimeoutSec = 20; UseBasicParsing = $true }
    # PS7 uses HttpResponseException instead of the PS5 WebException below.
    if ($PSVersionTable.PSVersion.Major -ge 7) { $reqArgs['SkipHttpErrorCheck'] = $true }
    if ($null -ne $Body) {
        $reqArgs['ContentType'] = 'application/json; charset=utf-8'
        $reqArgs['Body'] = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 20 -Compress))
    }
    # PS5 Invoke-WebRequest throws on 4xx/5xx; recover status + body from the exception.
    $status = 0; $content = ''; $traceId = $null
    try {
        $resp = Invoke-WebRequest @reqArgs
        $status = [int]$resp.StatusCode; $content = $resp.Content
        $traceId = $resp.Headers['X-Trace-Id']
    } catch [System.Net.WebException] {
        $r = $_.Exception.Response
        if (-not $r) { throw }
        $status = [int]$r.StatusCode
        $traceId = $r.Headers['X-Trace-Id']
        $sr = New-Object IO.StreamReader($r.GetResponseStream(), [Text.Encoding]::UTF8)
        $content = $sr.ReadToEnd(); $sr.Close()
    }
    if ($status -ne $Expect) { throw "expected $Expect got $status : $Method $Path`n$content" }
    if (-not $traceId) { throw "missing X-Trace-Id : $Method $Path" }
    if ($content) { return $content | ConvertFrom-Json }
    return $null
}

function Pass([string]$msg) { $script:step++; Write-Host ("  [{0:D2}] PASS {1}" -f $script:step, $msg) }

function Approve-Review([string]$reviewId, [string]$requester) {
    $detail = Invoke-Api 200 GET "/reviews/$reviewId" $requester
    if (-not $detail.steps -or $detail.steps.Count -eq 0) { throw "no independent reviewer: $reviewId" }
    $result = $detail
    foreach ($s in $detail.steps) {
        if ($s.state -eq 'PENDING') {
            $who = ($script:ids.GetEnumerator() | Where-Object { $_.Value -eq $s.reviewer_id } | Select-Object -First 1).Key
            $result = Invoke-Api 200 POST "/reviews/$reviewId/decision" $who @{ approve=$true; reason='review' }
        }
    }
    if ($result.status -ne 'APPROVED') { throw "review not approved: $reviewId -> $($result.status)" }
    return $result
}

function Register-Approve([string]$who, [string]$department, [int]$phoneSuffix) {
    $r = Invoke-Api 200 POST '/auth/register' $null @{ account=$who; password=$strongPassword; phone=("1380000{0:D4}" -f $phoneSuffix); name=$who; departmentId=$department }
    $script:ids[$who] = $r.id
    $login = Invoke-Api 200 POST '/auth/login' $null @{ account=$who; password=$strongPassword }
    $script:tokens[$who] = $login.token
    Invoke-Api 403 GET '/dashboard' $who | Out-Null   # pending account cannot read company data
    Approve-Review $r.reviewId $who | Out-Null
    return $r.reviewId
}

function Configure([string]$who, [hashtable]$changes) {
    $body = $changes.Clone()
    $body['version'] = (Invoke-Api 200 GET '/auth/me' $who).version
    $body['reason'] = 'org config'
    $r = Invoke-Api 200 POST "/organization/users/$($script:ids[$who])/revisions" $Admin $body
    Approve-Review $r.id $Admin | Out-Null
}

Write-Host "=== E2E core-link regression @ $BaseUrl ($businessDate) ==="

# 1. Health + OpenAPI contract
if ((Invoke-Api 200 GET '/health' $null).status -ne 'UP') { throw 'health not UP' }
Pass 'health UP'
$contract = Invoke-Api 200 GET '/openapi' $null
if ($contract.servers[0].url -ne '/' -or -not $contract.components.schemas.TaskDraft) { throw 'bad OpenAPI contract' }
Pass 'OpenAPI contract exposes TaskDraft'

# 2. Unauthenticated reject + admin forced password change
Invoke-Api 401 GET '/dashboard' $null | Out-Null
Pass 'unauthenticated dashboard -> 401'
$login = Invoke-Api 200 POST '/auth/login' $null @{ account=$Admin; password=$AdminPassword }
$script:tokens[$Admin] = $login.token
if (-not $login.user.must_change_password) { throw 'first login did not force password change' }
Invoke-Api 403 GET '/dashboard' $Admin | Out-Null
Pass 'dashboard before password change -> 403'
Invoke-Api 200 POST '/auth/password' $Admin @{ oldPassword=$AdminPassword; newPassword=$strongPassword } | Out-Null
Invoke-Api 401 GET '/auth/me' $Admin | Out-Null
$login = Invoke-Api 200 POST '/auth/login' $null @{ account=$Admin; password=$strongPassword }
$script:tokens[$Admin] = $login.token
$script:ids[$Admin] = (Invoke-Api 200 GET '/auth/me' $Admin).id
Pass 'admin re-login after password change'

# 3. Registration cannot escalate to admin
Invoke-Api 400 POST '/auth/register' $null @{ account='forged'; role='ADMIN'; password=$strongPassword; phone='13800009999'; name='forged'; departmentId='product' } | Out-Null
Pass 'register with role=ADMIN -> 400'

# 4. Independent reviewer: register reviewer then grant company-reviewer duty
Register-Approve 'reviewer' 'product' 2 | Out-Null
$reviewerMe = Invoke-Api 200 GET '/auth/me' 'reviewer'
$reviewerApp = Invoke-Api 200 POST '/organization/reviewer-application' 'reviewer' @{ version=$reviewerMe.version; reason='apply company reviewer' }
Approve-Review $reviewerApp.id 'reviewer' | Out-Null
Pass 'reviewer registered and granted company-reviewer duty'

# 5. Register employees across departments
Register-Approve 'leader' 'product'   11 | Out-Null
Register-Approve 'alice'  'product'   12 | Out-Null
Register-Approve 'bob'    'marketing' 13 | Out-Null
Pass 'leader/alice (product) + bob (marketing) registered and approved'

# 6. Build team + assign roles (through review chain backed by the company reviewer)
$teamReq = Invoke-Api 200 POST '/organization/teams/revisions' $Admin @{ name='product-team'; departmentId='product'; version=0; reason='create team' }
$team = $teamReq.target_id
Approve-Review $teamReq.id $Admin | Out-Null
Configure 'reviewer' @{ teamId=$team }
Configure 'alice'    @{ teamId=$team }
Configure 'leader'   @{ teamId=$team; role='LEADER' }
Pass 'team created; leader/alice/reviewer configured'

# 7. Organization data scope: leader dispatch range = own team active members only
$dispatch = Invoke-Api 200 GET '/organization/people?dispatch=true' 'leader'
$dispatchIds = @($dispatch.items | ForEach-Object { $_.id })
if (-not ($dispatchIds -contains $script:ids['alice'])) { throw 'dispatch range missing alice' }
if ($dispatchIds -contains $script:ids['bob']) { throw 'dispatch range leaked cross-dept bob' }
Pass "org scope correct (leader can dispatch alice, not cross-dept bob)"

# 8. Task dispatch + idempotency + authorization
$deadline = (Get-Date).Date.AddDays(1).AddHours(23).AddMinutes(59).ToString('yyyy-MM-ddTHH:mm:sszzz')
$startAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$taskBody = @{ title='product-task'; participants=@($script:ids['alice']); startAt=$startAt; deadline=$deadline; urgency='NORMAL'; content='task content' }
$created = Invoke-Api 200 POST '/tasks' 'leader' $taskBody 'product-task'
$task = $created.target_id
if ($created.status -ne 'PENDING' -or -not $task) { throw 'task creation did not return a pending review' }
Pass 'task creation returned pending review'
$replay = Invoke-Api 200 POST '/tasks' 'leader' $taskBody 'product-task'
if ($replay.id -ne $created.id) { throw 'idempotent replay returned different review' }
Pass 'same idempotency key replays same review'
$conflict = $taskBody.Clone(); $conflict['title'] = 'different content'
Invoke-Api 409 POST '/tasks' 'leader' $conflict 'product-task' | Out-Null
Pass 'idempotency key with different content -> 409'
Invoke-Api 403 POST '/tasks' 'alice' @{ title='employee dispatch'; ownerId=$script:ids['alice']; deadline=$deadline; urgency='NORMAL'; content='x'; collaborators=@() } 'employee-dispatch' | Out-Null
Pass 'employee without dispatch right -> 403'
Invoke-Api 404 GET "/tasks/$task" 'alice' | Out-Null
Approve-Review $created.id 'leader' | Out-Null
$effectiveTask = Invoke-Api 200 GET "/tasks/$task" 'alice'
if (-not ($effectiveTask.participants | Where-Object { $_.id -eq $script:ids['alice'] }) -or
    -not $effectiveTask.start_at) { throw 'approved task lost participants or start time' }
Pass 'task becomes visible after independent review with participants/start time'
$row = (Invoke-Api 200 GET '/tasks' 'alice').items[0]
foreach ($f in @('phase','status','completion','events')) {
    if ($row.PSObject.Properties.Name -contains $f) { throw "task list leaked forbidden field: $f" }
}
Pass 'task list has no phase/status/completion/events field'
$taskComment = Invoke-Api 200 POST "/tasks/$task/comments" 'leader' @{ text='task public comment' } 'task-comment-1'
$taskReply = Invoke-Api 200 POST "/tasks/$task/comments" 'alice' @{ text='task reply'; parentId=$taskComment.id } 'task-reply-1'
if ($taskReply.parent_id -ne $taskComment.id -or -not $taskReply.nickname) { throw 'task reply metadata missing' }
Invoke-Api 409 POST "/tasks/$task/comments" 'alice' @{ text='task reply'; parentId=$taskComment.id } 'task-reply-1' | Out-Null
Invoke-Api 400 POST "/tasks/$task/comments" 'alice' @{ text='no key' } | Out-Null
Invoke-Api 404 GET "/tasks/$task/comments" 'bob' | Out-Null
Pass 'task comments preserve reply relation, reject duplicate key/missing key and peer read'

# 9. Task lifecycle: received -> feedback -> accepted -> archived, version concurrency
$received = Invoke-Api 200 POST "/tasks/$task/events" 'alice' @{ type='RECEIVED'; version=1 }
Invoke-Api 409 POST "/tasks/$task/events" 'alice' @{ type='FEEDBACK'; text='x'; version=1 } | Out-Null
Pass 'stale version feedback -> 409'
$feedback = Invoke-Api 200 POST "/tasks/$task/events" 'alice' @{ type='FEEDBACK'; text='result'; version=$received.version }
$accepted = Invoke-Api 200 POST "/tasks/$task/events" 'leader' @{ type='ACCEPTED'; version=$feedback.version }
Invoke-Api 200 POST "/tasks/$task/events" 'leader' @{ type='ARCHIVED'; version=$accepted.version } | Out-Null
$events = (Invoke-Api 200 GET "/tasks/$task" 'alice').events
Pass "task lifecycle complete, timeline has $($events.Count) events"

# 10. Daily log: draft -> version conflict -> privacy -> submit -> subordinate entry
$logBody = @{ work='rd work'; blockers='pending dep'; tomorrow='continue'; taskIds=@($task) }
$draft = Invoke-Api 200 PUT '/logs/draft' 'alice' @{ businessDate=$businessDate; version=0; body=$logBody }
$log = $draft.id
$draft2 = Invoke-Api 200 PUT '/logs/draft' 'alice' @{ businessDate=$businessDate; version=1; body=$logBody }
if ($draft2.version -ne 2) { throw "draft version did not advance: $($draft2.version)" }
Invoke-Api 409 PUT '/logs/draft' 'alice' @{ businessDate=$businessDate; version=1; body=$logBody } | Out-Null
Pass 'daily log draft version conflict -> 409'
Invoke-Api 404 GET "/logs/$log" 'leader' | Out-Null
if ((Invoke-Api 200 GET "/logs?ownerId=$($script:ids['alice'])" 'leader').items.Count -ne 0) { throw 'leader saw unsubmitted draft' }
Pass 'unsubmitted draft invisible to manager'
Invoke-Api 403 GET "/logs?ownerId=$($script:ids['alice'])" 'bob' | Out-Null
Pass 'peer cross-read of logs -> 403'
$submitted = Invoke-Api 200 POST "/logs/$log/submit" 'alice' @{ version=2 }
if (-not $submitted.submittedAt -or -not $submitted.editableUntil -or
    -not $submitted.canEdit -or -not $submitted.canWithdraw) { throw 'missing diary edit capabilities' }
if (([DateTimeOffset]$submitted.editableUntil - [DateTimeOffset]$submitted.submittedAt).TotalHours -ne 24) {
    throw 'diary edit deadline is not 24 hours after first submission'
}
$sub = Invoke-Api 200 GET "/logs/subordinates?date=$businessDate" 'leader'
if ($sub.total -lt 1) { throw 'subordinate entry did not return submitted log' }
Invoke-Api 403 GET '/logs/subordinates' 'alice' | Out-Null
Pass "subordinate log entry shows submitted log (total=$($sub.total)); employee access -> 403"

# week6: current backend contract; revisions still require independent approval.
$filtered = Invoke-Api 200 GET "/logs/subordinates?departmentId=product&search=rd%20work&date=$businessDate" 'leader'
if (-not ($filtered.items | Where-Object { $_.id -eq $log })) { throw 'combined diary filters lost submitted diary' }
if (-not $filtered.groups -or -not $filtered.items[0].author.id -or
    $filtered.items[0].department.id -ne 'product') { throw 'missing department/author grouping' }
$empty = Invoke-Api 200 GET "/logs/subordinates?departmentId=unknown-week6&date=$businessDate" 'leader'
if ($empty.total -ne 0) { throw 'unknown department exposed logs' }
Invoke-Api 400 GET ('/logs/subordinates?search=' + ('x' * 101)) 'leader' | Out-Null
Pass 'department/search/date filters, grouping, unknown department and invalid search'
$comment = Invoke-Api 200 POST "/logs/$log/comments" 'leader' @{ text='week6 public comment' }
$reply = Invoke-Api 200 POST "/logs/$log/comments" 'alice' @{ text='week6 reply'; parentId=$comment.id }
if ($reply.parent_id -ne $comment.id -or -not $reply.author_name) { throw 'reply relation or author missing' }
$comments = Invoke-Api 200 GET "/logs/$log/comments" 'alice'
if (-not ($comments | Where-Object { $_.id -eq $reply.id -and $_.parent_id -eq $comment.id })) {
    throw 'reply did not round trip'
}
Invoke-Api 400 POST "/logs/$log/comments" 'alice' @{ text='' } | Out-Null
Invoke-Api 400 POST "/logs/$log/comments" 'alice' @{ text='invalid reply'; parentId='missing-week6-comment' } | Out-Null
Invoke-Api 404 GET "/logs/$log/comments" 'bob' | Out-Null
Pass 'public comment/reply round trip, empty text, invalid parent and peer denial'

# 11. Notification center reachable
$notif = Invoke-Api 200 GET '/notifications' 'alice'
Pass "notification center reachable (alice total=$($notif.total))"

Write-Host "`n=== all $script:step core-link assertions passed ==="
