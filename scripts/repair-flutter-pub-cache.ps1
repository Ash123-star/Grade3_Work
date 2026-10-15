[CmdletBinding()]
param(
    [string]$FlutterSdk,
    [string]$CachePath,
    [switch]$Online
)

$ErrorActionPreference = 'Stop'
$repairProject = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mobile'))
$repairConfigFile = Join-Path $repairProject '.dart_tool/package_config.json'
$repairConfig = if (Test-Path -LiteralPath $repairConfigFile) {
    Get-Content -LiteralPath $repairConfigFile -Raw | ConvertFrom-Json
} else { $null }
if (-not $FlutterSdk) {
    if ($repairConfig.flutterRoot) {
        $FlutterSdk = ([Uri]$repairConfig.flutterRoot).LocalPath
    } else {
        $repairFlutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
        if (-not $repairFlutterCommand) { throw '请通过 -FlutterSdk 指定 Flutter SDK 路径。' }
        $FlutterSdk = Split-Path (Split-Path $repairFlutterCommand.Source -Parent) -Parent
    }
}
$FlutterSdk = [System.IO.Path]::GetFullPath($FlutterSdk)
if (-not $CachePath) {
    $CachePath = Join-Path ([System.IO.Path]::GetPathRoot($FlutterSdk)) 'FlutterPubCache'
}
$CachePath = [System.IO.Path]::GetFullPath($CachePath)
if ($CachePath -match '[^\x00-\x7F]') {
    throw 'Pub 缓存必须使用纯英文路径，例如 D:\FlutterPubCache；未修改环境或缓存。'
}
if ((Test-Path -LiteralPath $CachePath) -and -not (Test-Path -LiteralPath $CachePath -PathType Container)) {
    throw '缓存目标已被文件占用，请换一个目录。'
}
$repairDart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$repairTool = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
if (-not (Test-Path -LiteralPath $repairDart) -or -not (Test-Path -LiteralPath $repairTool)) {
    throw 'Flutter SDK 未完成初始化，找不到 Dart 或 flutter_tools.snapshot。'
}
$repairLock = Join-Path $repairProject 'pubspec.lock'
if (-not (Test-Path -LiteralPath $repairLock)) { throw '缺少 pubspec.lock，不能保证锁定版本。' }
$repairLockHash = (Get-FileHash -LiteralPath $repairLock -Algorithm SHA256).Hash
$repairOldCache = if ($repairConfig.pubCache) {
    ([Uri]$repairConfig.pubCache).LocalPath
} elseif ($env:PUB_CACHE) { $env:PUB_CACHE } else {
    Join-Path $env:LOCALAPPDATA 'Pub/Cache'
}
$repairOldCache = [System.IO.Path]::GetFullPath($repairOldCache)
New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
if ($repairConfig -and $repairOldCache -ne $CachePath) {
    $repairBaseUri = [Uri]::new($repairConfigFile)
    $repairPrefix = $repairOldCache.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($repairPackage in $repairConfig.packages) {
        $repairSource = [Uri]::new($repairBaseUri, [string]$repairPackage.rootUri).LocalPath
        if (-not $repairSource.StartsWith($repairPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $repairSource -PathType Container)) { continue }
        $repairRelative = $repairSource.Substring($repairPrefix.Length).TrimEnd('\', '/')
        $repairDestination = Join-Path $CachePath $repairRelative
        $repairParent = Split-Path $repairDestination -Parent
        New-Item -ItemType Directory -Path $repairParent -Force | Out-Null
        $repairRobocopyLog = Join-Path $env:TEMP 'flutter-pub-cache-repair.log'
        & robocopy $repairSource $repairDestination /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 `
            /XD build .dart_tool .gradle .idea | Out-File -LiteralPath $repairRobocopyLog -Append
        if ($LASTEXITCODE -gt 7) { throw "复制包失败：$($repairPackage.name)，详见 $repairRobocopyLog" }
    }
    # Hashes and hosted version metadata allow official offline lock verification.
    foreach ($repairExtra in @('hosted-hashes', 'hosted/pub.dev/.cache')) {
        $repairSource = Join-Path $repairOldCache $repairExtra
        if (Test-Path -LiteralPath $repairSource -PathType Container) {
            $repairParent = Split-Path (Join-Path $CachePath $repairExtra) -Parent
            New-Item -ItemType Directory -Path $repairParent -Force | Out-Null
            Copy-Item -LiteralPath $repairSource -Destination $repairParent -Recurse -Force
        }
    }
}
$repairPreviousProcessCache = $env:PUB_CACHE
$env:PUB_CACHE = $CachePath
Push-Location $repairProject
try {
    $repairArguments = @($repairTool, '--no-version-check', 'pub', 'get', '--enforce-lockfile')
    if (-not $Online) { $repairArguments += '--offline' }
    & $repairDart @repairArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Pub 解析失败，未修改用户环境。离线缺包时可加 -Online 从 pub.dev 获取锁定依赖。'
    }
    if ((Get-FileHash -LiteralPath $repairLock -Algorithm SHA256).Hash -ne $repairLockHash) {
        throw 'pubspec.lock 意外变化，停止配置环境；请检查差异。'
    }
    $repairResolved = Get-Content -LiteralPath $repairConfigFile -Raw | ConvertFrom-Json
    $repairBaseUri = [Uri]::new($repairConfigFile)
    foreach ($repairPackage in $repairResolved.packages) {
        $repairUri = [Uri]::new($repairBaseUri, [string]$repairPackage.rootUri)
        if (-not (Test-Path -LiteralPath $repairUri.LocalPath -PathType Container)) {
            throw "包目录不存在：$($repairPackage.name)；未修改用户环境。"
        }
        if ($repairUri.LocalPath -match '[^\x00-\x7F]') {
            throw "包目录仍含非ASCII字符：$($repairPackage.name)；未修改用户环境。"
        }
    }
    [Environment]::SetEnvironmentVariable('PUB_CACHE', $CachePath, 'User')
    Write-Output "依赖恢复成功，锁文件未变；用户 PUB_CACHE=$CachePath。"
    Write-Output '请完全退出并重新打开 Android Studio，再运行原来的 Flutter 配置。未构建 APK，也未确认模拟器运行。'
} finally {
    Pop-Location
    $env:PUB_CACHE = $repairPreviousProcessCache
}
