[CmdletBinding()]
param(
  [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude')
)
$ErrorActionPreference = 'Stop'

$hooksDir = Join-Path $ClaudeDir 'hooks'
foreach ($f in 'claude-record-window.ps1','notify-toast.ps1','claudefocus.exe') {
  $p = Join-Path $hooksDir $f
  if (Test-Path $p) { Remove-Item $p -Force; Write-Host "Removed $p" }
}

$base = 'HKCU:\SOFTWARE\Classes\claudefocus'
if (Test-Path $base) { Remove-Item $base -Recurse -Force; Write-Host "Removed claudefocus: protocol" }

# Restore newest settings backup
$settingsPath = Join-Path $ClaudeDir 'settings.json'
$backup = Get-ChildItem (Split-Path $settingsPath) -Filter 'settings.json.bak-*' -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending | Select-Object -First 1
if ($backup) {
  Copy-Item $backup.FullName $settingsPath -Force
  Write-Host "Restored settings.json from $($backup.Name)"
} else {
  Write-Host "No settings backup found. Remove the Notification/Stop/UserPromptSubmit hooks manually if desired." -ForegroundColor Yellow
}

Write-Host "Uninstall complete. Restart Claude Code." -ForegroundColor Green
