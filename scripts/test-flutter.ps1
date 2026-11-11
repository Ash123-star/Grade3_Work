param([string]$Flutter = 'flutter',[string]$ResultsDirectory = 'output/flutter-regression')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$results = Join-Path $repoRoot $ResultsDirectory
New-Item -ItemType Directory -Force -Path $results | Out-Null
$http = @('ai_map_ui_test.dart','ai_workbench_test.dart','member_workspace_contract_test.dart','attachment_assignment_http_test.dart','read_http_contract_test.dart','task_label_selector_test.dart','holiday_http_test.dart','notification_page_http_test.dart','live_notifications_contract_test.dart')
$previousTemp=$env:TEMP; $previousTmp=$env:TMP
Push-Location (Join-Path $repoRoot 'mobile')
try {
    $env:TEMP=$results; $env:TMP=$results
    & $Flutter test --no-pub --dart-define=USE_MOCK=false @($http | ForEach-Object { 'test/'+$_ }) --reporter expanded *> (Join-Path $results 'http.log')
    $httpExit=$LASTEXITCODE
    $mock=Get-ChildItem test/*_test.dart | Where-Object { $_.Name -notin $http -or $_.Name -eq 'live_notifications_contract_test.dart' } | ForEach-Object { 'test/'+$_.Name }
    & $Flutter test --no-pub --dart-define=USE_MOCK=true @mock --reporter expanded *> (Join-Path $results 'mock.log')
    $mockExit=$LASTEXITCODE
    @{http=$httpExit;mock=$mockExit} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $results 'exit-codes.json')
    if ($httpExit -ne 0 -or $mockExit -ne 0) {throw "Flutter回归失败，见 $results"}
    Write-Output "Flutter回归通过，见 $results；真实服务 opt-in 测试的跳过状态须另行核对。"
} finally {Pop-Location; $env:TEMP=$previousTemp; $env:TMP=$previousTmp}
