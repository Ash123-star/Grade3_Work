param([string]$Flutter='flutter')
$ErrorActionPreference='Stop'
$ossRoot=Split-Path -Parent $PSScriptRoot
$ossStage=[IO.Path]::GetFullPath((Join-Path $ossRoot 'output/oss/flutter-assets'))
$ossExpected=[IO.Path]::GetFullPath((Join-Path $ossRoot 'output/oss'))+[IO.Path]::DirectorySeparatorChar
if(-not $ossStage.StartsWith($ossExpected,[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid OSS staging directory'}
Push-Location (Join-Path $ossRoot 'mobile')
try{
    & $Flutter build bundle --no-pub
    if($LASTEXITCODE -ne 0){throw 'Flutter asset bundle build failed'}
}finally{Pop-Location}
$ossBundle=Join-Path $ossRoot 'mobile/build/flutter_assets'
if(-not (Test-Path -LiteralPath (Join-Path $ossBundle 'FontManifest.json'))){throw 'Flutter FontManifest is missing'}
if(Test-Path -LiteralPath $ossStage){Remove-Item -LiteralPath $ossStage -Recurse -Force}
New-Item -ItemType Directory -Force -Path (Join-Path $ossStage 'fonts') | Out-Null
$ossCopied=0
foreach($ossArea in @('fonts','packages')){
    $ossSource=Join-Path $ossBundle $ossArea
    if(-not (Test-Path -LiteralPath $ossSource)){continue}
    foreach($ossFile in Get-ChildItem -LiteralPath $ossSource -File -Recurse){
        # 仅发布图片、字体和许可证等资源文件，执行代码仍随应用发布。
        if(@('.png','.jpg','.jpeg','.webp','.gif','.svg','.ttf','.ttc','.otf','.woff','.woff2','.txt','.md','.json') -contains $ossFile.Extension.ToLowerInvariant()){
            $ossRelative=$ossFile.FullName.Substring($ossBundle.Length+1)
            $ossTarget=Join-Path $ossStage $ossRelative
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ossTarget) | Out-Null
            Copy-Item -LiteralPath $ossFile.FullName -Destination $ossTarget
            $ossCopied++
        }
    }
}
Copy-Item -LiteralPath (Join-Path $ossBundle 'FontManifest.json') -Destination (Join-Path $ossStage 'fonts/FontManifest.json')
$ossNotice=Join-Path $ossBundle 'NOTICES.Z'
if(Test-Path -LiteralPath $ossNotice){
    $ossSourceStream=[IO.File]::OpenRead($ossNotice)
    $ossInflater=New-Object IO.Compression.GZipStream($ossSourceStream,[IO.Compression.CompressionMode]::Decompress)
    try{$ossOutputStream=[IO.File]::Create((Join-Path $ossStage 'fonts/DEPENDENCY-NOTICES.txt'));try{$ossInflater.CopyTo($ossOutputStream)}finally{$ossOutputStream.Dispose()}}finally{$ossInflater.Dispose();$ossSourceStream.Dispose()}
}elseif(Test-Path -LiteralPath (Join-Path $ossBundle 'NOTICES')){
    Copy-Item -LiteralPath (Join-Path $ossBundle 'NOTICES') -Destination (Join-Path $ossStage 'fonts/DEPENDENCY-NOTICES.txt')
}else{throw 'Flutter dependency licenses are missing'}
$ossFontManifest=Get-Content -Raw -LiteralPath (Join-Path $ossStage 'fonts/FontManifest.json') | ConvertFrom-Json
foreach($ossFamily in $ossFontManifest){foreach($ossFont in $ossFamily.fonts){
    $ossFontPath=if($ossFont.asset.StartsWith('assets/')){Join-Path $ossRoot ('mobile/'+$ossFont.asset)}else{Join-Path $ossStage $ossFont.asset}
    if(-not (Test-Path -LiteralPath $ossFontPath)){throw "Declared font missing: $($ossFont.asset)"}
}}
Write-Output "OSS_RUNTIME_ASSETS_PREPARED=$ossCopied"
