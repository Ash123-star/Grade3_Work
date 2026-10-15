param(
  [string]$Source = (Join-Path $PSScriptRoot '..\assets\new'),
  [string]$Output = (Join-Path $PSScriptRoot '..\assets\generated_ui\new_pack'),
  [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
# ASCII entry point is safe in both Windows PowerShell 5.1 and PowerShell 7.
# Pillow/NumPy process paths through Unicode; source images are never modified.
& $Python (Join-Path $PSScriptRoot 'process_new_ui_assets.py') --source $Source --output $Output
if ($LASTEXITCODE -ne 0) { throw "UI asset processing failed with exit code $LASTEXITCODE" }
