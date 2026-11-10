param(
  [string]$ClaudeDir = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$claude = Get-ClaudeDir $ClaudeDir
$installDir = Join-Path $claude 'hooks\claude-notify'
$settingsPath = Join-Path $claude 'settings.json'

Write-Host 'Uninstalling Claude Code notifications'

if (Test-Path $settingsPath) {
  $settings = Read-Settings $settingsPath
  $removed = Remove-NotifyHooks $settings
  if ($removed -gt 0) {
    $backup = Backup-Settings $settingsPath
    Write-Host "  backed up settings to $backup"
    Write-Settings $settings $settingsPath
  }
  Write-Host "  removed $removed hook(s) from $settingsPath"
}

[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($ProtocolKey, $false)
Write-Host '  removed claudefocus: protocol'

if (Test-Path $installDir) {
  Remove-Item $installDir -Recurse -Force
  Write-Host "  deleted $installDir"
}

$tempDir = Join-Path $env:TEMP 'claude-code-windows'
if (Test-Path $tempDir) {
  Remove-Item $tempDir -Recurse -Force
}
$legacy = Join-Path $env:TEMP 'claude-code-window.txt'
if (Test-Path $legacy) {
  Remove-Item $legacy -Force
}

Write-Host ''
Write-Host 'Done. Restart any open Claude Code sessions.'
