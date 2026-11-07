[CmdletBinding()]
param([string]$FlutterSdk='D:/flutter',[string]$Device='emulator-5554',[int]$Port=18088,[switch]$SkipBuild,[switch]$KeepEnvironment,[string]$ApiContainer,[string]$DataContainer,[ValidateRange(1,60)][int]$TaskDays=3,[switch]$CrowdedTarget)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$suffix=[Guid]::NewGuid().ToString('N').Substring(0,10)
$container="workpanel-calendar-live-$suffix"
$dir=Join-Path $root "output/calendar-live-$suffix"
$created=$false;$apiProcess=$null
$names=@('DB_URL','DB_USER','DB_PASSWORD','REDIS_HOST','REDIS_PORT','REDIS_PASSWORD','NEO4J_URI','ADMIN_ACCOUNT','ADMIN_PASSWORD','ADMIN_PHONE','SERVER_PORT','JOBS_ENABLED','CALENDAR_MOVE_ENABLED','CALENDAR_EVIDENCE_DIR')
$saved=@{};foreach($key in $names){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
New-Item -ItemType Directory -Path $dir | Out-Null
Push-Location $root
try {
    if($ApiContainer) {
        if(!$DataContainer){throw 'DataContainer is required with ApiContainer'}
        $container=$DataContainer
        if((docker inspect $ApiContainer --format '{{.State.Running}}') -ne 'true'){throw 'Docker API is not running'}
        if((docker inspect $container --format '{{.State.Running}}') -ne 'true'){throw 'Docker data container is not running'}
        $null=Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 5
    } else {
    if(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue){throw "Test API port $Port is occupied"}
    if(!$SkipBuild){
        & cmd.exe /d /c 'mvn.cmd -B -f server/pom.xml -DskipTests package 2>&1' *> "$dir/build.log"
        if($LASTEXITCODE -ne 0){throw "API build failed: $dir/build.log"}
    }
    $password=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
    $redisScripts=Join-Path $root 'deploy/redis'
    docker run -d --name $container -p '127.0.0.1::5432' -p '127.0.0.1::6379' -p '127.0.0.1::7687' --volume "${redisScripts}:/opt/redis:ro" -e POSTGRES_DB=workpanel -e POSTGRES_USER=workpanel -e "POSTGRES_PASSWORD=$password" -e "REDIS_PASSWORD=$password" -e "NEO4J_PASSWORD=$password" collaboration-data-runtime:local | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Disposable data container could not start'};$created=$true
    $ready=$false
    for($i=0;$i -lt 90;$i++){
        $ErrorActionPreference='Continue';docker exec $container sh /opt/runtime/health.sh *> $null;$health=$LASTEXITCODE;$ErrorActionPreference='Stop'
        if($health -eq 0){$ready=$true;break};Start-Sleep -Seconds 1
    }
    if(!$ready){throw 'Disposable data container did not become healthy'}
    $pg=(docker port $container 5432/tcp).Split(':')[-1]
    $env:DB_URL="jdbc:postgresql://127.0.0.1:$pg/workpanel";$env:DB_USER='workpanel';$env:DB_PASSWORD=$password
    $env:REDIS_HOST='127.0.0.1';$env:REDIS_PORT=(docker port $container 6379/tcp).Split(':')[-1];$env:REDIS_PASSWORD=$password
    $env:NEO4J_URI='';$env:ADMIN_ACCOUNT='calendar-live-admin';$env:ADMIN_PASSWORD=$password;$env:ADMIN_PHONE='13900000001'
    $env:SERVER_PORT="$Port";$env:JOBS_ENABLED='false';$env:CALENDAR_MOVE_ENABLED='true'
    $java=(Get-Command java.exe -ErrorAction Stop).Source
    $jar=Join-Path $root 'server/target/collaboration-server-1.0.0.jar'
    $apiProcess=Start-Process -FilePath $java -ArgumentList '-Xms64m','-Xmx384m','-XX:+UseSerialGC','-jar',('"'+$jar+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput "$dir/api.log" -RedirectStandardError "$dir/api-error.log" -PassThru
    $ready=$false
    for($i=0;$i -lt 60;$i++){
        if($apiProcess.HasExited){throw "Test API exited: $dir/api.log"}
        try{$null=Invoke-RestMethod "http://127.0.0.1:$Port/api/health" -TimeoutSec 2;$ready=$true;break}catch{Start-Sleep -Seconds 1}
    }
    if(!$ready){throw 'Test API health timeout'}
    }
    $company="calendar-$suffix";$issuer="$company-issuer";$reviewer="$company-reviewer";$participant="$company-participant";$task="$company-task"
    # The current form reads the company's label catalog; fixtures use isolated IDs.
    $labelId="$company-label"
    $issuerToken=[Guid]::NewGuid().ToString('N');$reviewerToken=[Guid]::NewGuid().ToString('N')
    $sha=[Security.Cryptography.SHA256]::Create()
    $issuerHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($issuerToken)))).Replace('-','').ToLowerInvariant()
    $reviewerHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($reviewerToken)))).Replace('-','').ToLowerInvariant();$sha.Dispose()
    $first=(Get-Date -Day 1).Date.AddMonths(1);$last=$first.AddMonths(1).AddDays(-1);$begin=$last.AddDays(1-$TaskDays)
    $startAt=$begin.ToString('yyyy-MM-dd')+'T09:00:00+08:00';$deadline=$last.ToString('yyyy-MM-dd')+'T18:00:00+08:00'
    $sql=@"
INSERT INTO companies(id,name) VALUES ('$company','Calendar device fixture');
INSERT INTO departments(id,company_id,name) VALUES ('$company-d','$company','Device department');
INSERT INTO teams(id,company_id,department_id,name) VALUES ('$company-t','$company','$company-d','Device team');
INSERT INTO users(id,company_id,account,password_hash,phone,name,department_id,team_id,role,status,dispatch_enabled,company_reviewer) VALUES
('$issuer','$company','$issuer','x','$issuer','DeviceIssuer','$company-d','$company-t','LEADER','ACTIVE',true,false),
('$reviewer','$company','$reviewer','x','$reviewer','DeviceReviewer','$company-d','$company-t','EMPLOYEE','ACTIVE',false,true),
('$participant','$company','$participant','x','$participant','DeviceParticipant','$company-d','$company-t','EMPLOYEE','ACTIVE',false,false);
INSERT INTO reporting_relations(employee_id,manager_id,company_id) VALUES ('$issuer','$reviewer','$company');
INSERT INTO task_labels(id,company_id,department_id,name,category,color,creator_id) VALUES ('$labelId','$company','$company-d','Calendar device label','CUSTOM','#4A90E2','$issuer');
INSERT INTO sessions VALUES ('$issuerHash','$issuer',now()+interval '2 hours'),('$reviewerHash','$reviewer',now()+interval '2 hours');
INSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version) VALUES
('$task','$company','$participant','$issuer','Android calendar task','$startAt','$deadline','{"title":"Android calendar task","participants":["$participant","$reviewer","$issuer"],"startAt":"$startAt","deadline":"$deadline","urgency":"NORMAL","attachments":[]}','DISPATCHED',1);
INSERT INTO task_participants(company_id,task_id,user_id) VALUES ('$company','$task','$participant'),('$company','$task','$reviewer'),('$company','$task','$issuer');
"@
    if($CrowdedTarget){
        $busyStart=$last.AddDays(1).ToString('yyyy-MM-dd')+'T09:00:00+08:00'
        $busyEnd=$last.AddDays(10).ToString('yyyy-MM-dd')+'T18:00:00+08:00'
        for($i=0;$i -lt 5;$i++){
            $busyId="$company-busy-$i"
            $sql+="`nINSERT INTO tasks(id,company_id,owner_id,issuer_id,title,start_at,deadline,body,phase,version) VALUES ('$busyId','$company','$participant','$issuer','Occupied row $i','$busyStart','$busyEnd','{`"title`":`"Occupied row $i`",`"participants`":[`"$participant`",`"$reviewer`",`"$issuer`"],`"startAt`":`"$busyStart`",`"deadline`":`"$busyEnd`",`"urgency`":`"NORMAL`",`"attachments`":[]}','DISPATCHED',1);"
            $sql+="`nINSERT INTO task_participants(company_id,task_id,user_id) VALUES ('$company','$busyId','$participant'),('$company','$busyId','$reviewer'),('$company','$busyId','$issuer');"
        }
    }
    [IO.File]::WriteAllText("$dir/fixture.sql",$sql,(New-Object Text.UTF8Encoding($false)))
    docker cp "$dir/fixture.sql" "${container}:/tmp/calendar-fixture.sql" | Out-Null
    docker exec $container psql -U workpanel -d workpanel -v ON_ERROR_STOP=1 -f /tmp/calendar-fixture.sql *> "$dir/fixture.log"
    if($LASTEXITCODE -ne 0){throw "Fixture failed: $dir/fixture.log"}
    $defines=@{USE_MOCK='false';API_BASE_URL="http://10.0.2.2:$Port/api";CALENDAR_TEST_TOKEN=$issuerToken;CALENDAR_REVIEWER_TOKEN=$reviewerToken;CALENDAR_COMPANY=$company;CALENDAR_ISSUER=$issuer;CALENDAR_TASK_ID=$task;CALENDAR_LABEL_ID=$labelId}
    $defineFile="$dir/test-defines.json";[IO.File]::WriteAllText($defineFile,($defines|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    Push-Location (Join-Path $root 'mobile')
    try {
        $ErrorActionPreference='Continue'
        $env:CALENDAR_EVIDENCE_DIR=$dir
        & "$FlutterSdk/bin/flutter.bat" --no-version-check drive --driver=test_driver/calendar_live_driver.dart --target=integration_test/calendar_task_live_test.dart -d $Device "--dart-define-from-file=$defineFile" *> "$dir/android-test.log"
        $testCode=$LASTEXITCODE;$ErrorActionPreference='Stop'
    } finally { Pop-Location }
    docker exec $container psql -U workpanel -d workpanel -c "SELECT id,start_at,deadline,version FROM tasks WHERE company_id='$company'; SELECT id,kind,status,target_id FROM review_requests WHERE company_id='$company'; SELECT task_id,review_id FROM task_reschedule_commands WHERE company_id='$company';" *> "$dir/database-after.txt"
    if($testCode -ne 0){throw "Android calendar test failed: $dir/android-test.log"}
    Write-Output "CALENDAR_ANDROID_LIVE_PASSED evidence=$dir"
} finally {
    if(!$KeepEnvironment){
        if($apiProcess -and !$apiProcess.HasExited){Stop-Process -Id $apiProcess.Id}
        if($created){docker rm -fv $container | Out-Null}
        if($defineFile -and (Test-Path -LiteralPath $defineFile)){Remove-Item -LiteralPath $defineFile}
    } else { Write-Output "Retained isolated environment: $dir" }
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
}
