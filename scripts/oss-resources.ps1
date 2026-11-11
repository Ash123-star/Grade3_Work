param(
    [ValidateSet('inventory','probe','publish','migrate','purge','restore')][string]$Command='inventory',
    [string]$Release=('oss-'+(Get-Date -Format 'yyyyMMdd-HHmmss')),
    [switch]$Apply,
    [string]$EnvironmentFile='deploy/backend/.env',
    [string]$BackupFile
)
$ErrorActionPreference='Stop'
$ossRepoRoot=Split-Path -Parent $PSScriptRoot
$ossSaved=@{}
try {
    $ossEnvPath=if([IO.Path]::IsPathRooted($EnvironmentFile)){$EnvironmentFile}else{Join-Path $ossRepoRoot $EnvironmentFile}
    if(Test-Path -LiteralPath $ossEnvPath){
        foreach($ossLine in Get-Content -LiteralPath $ossEnvPath){
            if($ossLine -match '^\s*([A-Z][A-Z0-9_]*)\s*=(.*)$'){
                $ossName=$matches[1]
                $ossValue=$matches[2].Trim().Trim('"').Trim("'")
                if($ossName -notmatch '^(OSS_|DB_|POSTGRES_PORT$)'){continue}
                $ossSaved[$ossName]=[Environment]::GetEnvironmentVariable($ossName,'Process')
                [Environment]::SetEnvironmentVariable($ossName,$ossValue,'Process')
            }
        }
    }
    if(-not $env:DB_URL -and $env:POSTGRES_PORT){$ossSaved['DB_URL']=$null;$env:DB_URL="jdbc:postgresql://127.0.0.1:$($env:POSTGRES_PORT)/workpanel"}
    if($Release -notmatch '^[a-zA-Z0-9_-]{1,80}$'){throw 'Invalid release name'}
    $ossArguments='"'+$Command+'" "'+$ossRepoRoot+'" "'+$Release+'" '+$(if($Apply){'apply'}else{'dry-run'})
    if($BackupFile){$ossArguments+=' "'+[IO.Path]::GetFullPath($BackupFile)+'"'}
    Push-Location $ossRepoRoot
    try {
        & mvn.cmd -q -f server/pom.xml exec:java '-Dexec.mainClass=cn.workpanel.tools.OssResourceTool' "-Dexec.args=$ossArguments"
        if($LASTEXITCODE -ne 0){throw 'OSS resource operation failed; see sanitized error and output/oss report'}
    } finally {Pop-Location}
} finally {foreach($ossName in $ossSaved.Keys){[Environment]::SetEnvironmentVariable($ossName,$ossSaved[$ossName],'Process')}}
