[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64', 'arm', 'ia32')]
    [string[]]$Architectures = @('x64', 'arm64', 'arm'),
    [string]$LocalAssetDirectory
)

$ErrorActionPreference = 'Stop'
$sqliteProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mobile'))
$sqliteConfigFile = Join-Path $sqliteProject '.dart_tool/package_config.json'
if (-not (Test-Path -LiteralPath $sqliteConfigFile)) { throw 'Run Flutter pub get first.' }
$sqliteConfig = Get-Content -LiteralPath $sqliteConfigFile -Raw | ConvertFrom-Json
$sqlitePackage = $sqliteConfig.packages | Where-Object { $_.name -eq 'sqlite3' }
if (-not $sqlitePackage) { throw 'sqlite3 package is missing from package configuration.' }
$sqlitePackageRoot = [Uri]::new([Uri]::new($sqliteConfigFile), [string]$sqlitePackage.rootUri).LocalPath
$sqlitePackageSpec = Get-Content -LiteralPath (Join-Path $sqlitePackageRoot 'pubspec.yaml') -Raw
$sqliteVersionMatch = [regex]::Match($sqlitePackageSpec, '(?m)^version:\s*(\d+\.\d+\.\d+)\s*$')
if (-not $sqliteVersionMatch.Success) { throw 'Cannot identify locked sqlite3 version.' }
$sqliteVersion = $sqliteVersionMatch.Groups[1].Value
$sqliteHashes = Get-Content -LiteralPath (Join-Path $sqlitePackageRoot 'lib/src/hook/asset_hashes.dart') -Raw
$sqlitePersistent = Join-Path $sqliteProject ".native-cache/sqlite3-$sqliteVersion"
$sqliteShared = Join-Path $sqliteProject '.dart_tool/hooks_runner/shared/sqlite3/build'
$sqliteRelease = $null
$sqliteCurl = (Get-Command curl.exe -ErrorAction Stop).Source
foreach ($sqliteArchitecture in ($Architectures | Select-Object -Unique)) {
    $sqliteFilename = "libsqlite3.$sqliteArchitecture.android.so"
    $sqliteHashPattern = "'" + [regex]::Escape($sqliteFilename) + "':\s*'([a-f0-9]{64})'"
    $sqliteHashMatch = [regex]::Match($sqliteHashes, $sqliteHashPattern)
    if (-not $sqliteHashMatch.Success) { throw "Package has no SHA256 for $sqliteFilename." }
    $sqliteExpected = $sqliteHashMatch.Groups[1].Value
    $sqliteFile = Join-Path $sqlitePersistent $sqliteFilename
    New-Item -ItemType Directory -Path $sqlitePersistent -Force | Out-Null
    if (-not (Test-Path -LiteralPath $sqliteFile) -or
        (Get-FileHash -LiteralPath $sqliteFile -Algorithm SHA256).Hash -ne $sqliteExpected) {
        $sqlitePending = "$sqliteFile.pending"
        if ($LocalAssetDirectory) {
            $sqliteLocal = Join-Path $LocalAssetDirectory $sqliteFilename
            if (-not (Test-Path -LiteralPath $sqliteLocal)) { throw "Local asset not found: $sqliteFilename" }
            Copy-Item -LiteralPath $sqliteLocal -Destination $sqlitePending -Force
        } else {
            if (-not $sqliteRelease) {
                $sqliteMetadata = Join-Path $sqlitePersistent 'release.json'
                $sqliteApiUrl = "https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/sqlite3-$sqliteVersion"
                & $sqliteCurl --silent --show-error --fail --location --connect-timeout 10 --max-time 60 `
                    --header 'Accept: application/vnd.github+json' --output $sqliteMetadata $sqliteApiUrl
                if ($LASTEXITCODE -ne 0) { throw 'Official GitHub release metadata download failed; existing cache retained.' }
                $sqliteRelease = Get-Content -LiteralPath $sqliteMetadata -Raw | ConvertFrom-Json
            }
            $sqliteAsset = $sqliteRelease.assets | Where-Object { $_.name -eq $sqliteFilename }
            if (-not $sqliteAsset -or $sqliteAsset.url -notmatch '^https://api\.github\.com/repos/simolus3/sqlite3\.dart/releases/assets/\d+$') {
                throw "Matching official asset unavailable: $sqliteFilename"
            }
            & $sqliteCurl --silent --show-error --fail --location --connect-timeout 10 --max-time 60 `
                --header 'Accept: application/octet-stream' --output $sqlitePending $sqliteAsset.url
            if ($LASTEXITCODE -ne 0) { throw "Official download failed: $sqliteFilename; existing cache retained." }
        }
        if ((Get-FileHash -LiteralPath $sqlitePending -Algorithm SHA256).Hash -ne $sqliteExpected) {
            throw "SHA256 mismatch: $sqliteFilename; bytes were NOT installed into hook cache."
        }
        Move-Item -LiteralPath $sqlitePending -Destination $sqliteFile -Force
    }
    $sqliteHookDirectory = Join-Path $sqliteShared "download-$($sqliteExpected.Substring(0, 8))"
    New-Item -ItemType Directory -Path $sqliteHookDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sqliteFile -Destination (Join-Path $sqliteHookDirectory 'libsqlite3.so') -Force
    Write-Output "$sqliteFilename verified: $sqliteExpected; hook cache ready."
}
Write-Output 'SQLite native preparation completed; no APK build was performed. Re-run after flutter clean.'
