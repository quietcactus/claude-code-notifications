param(
  [string]$ClaudeDir = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$claude = Get-ClaudeDir $ClaudeDir
$installDir = Join-Path $claude 'hooks\claude-notify'
$settingsPath = Join-Path $claude 'settings.json'
$payload = Join-Path $PSScriptRoot 'payload'

Write-Host "Installing Claude Code notifications into $installDir"

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item (Join-Path $payload '*') $installDir -Force

$csc = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
  "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) {
  throw 'C# compiler (.NET Framework 4 csc.exe) not found.'
}

$exe = Join-Path $installDir 'claudefocus.exe'
$cs = Join-Path $installDir 'claude-focus.cs'
& $csc -nologo -target:winexe "-out:$exe" $cs | Out-Host
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) {
  throw 'Failed to compile claudefocus.exe'
}
Write-Host '  compiled claudefocus.exe'

$root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($ProtocolKey)
$root.SetValue('', 'URL:claudefocus')
$root.SetValue('URL Protocol', '')
$root.Close()
$cmdKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$ProtocolKey\shell\open\command")
$cmdKey.SetValue('', "`"$exe`" `"%1`"")
$cmdKey.Close()
Write-Host '  registered claudefocus: protocol'

$backup = Backup-Settings $settingsPath
if ($backup) {
  Write-Host "  backed up settings to $backup"
}

$settings = Read-Settings $settingsPath
$removed = Remove-NotifyHooks $settings
if ($removed -gt 0) {
  Write-Host "  replaced $removed existing notification hook(s)"
}

$dir = $installDir -replace '\\', '/'
$ps = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File'
Add-NotifyHook $settings 'UserPromptSubmit' "$ps `"$dir/claude-record-window.ps1`""
Add-NotifyHook $settings 'Stop' "$ps `"$dir/notify-toast.ps1`" -Title `"Claude Code`" -Message `"Done`""
Add-NotifyHook $settings 'Notification' "$ps `"$dir/notify-toast.ps1`" -Title `"Claude Code`" -Message `"Needs your input`""
Write-Settings $settings $settingsPath
Write-Host "  added hooks to $settingsPath"

Write-Host ''
Write-Host 'Done. Restart any open Claude Code sessions to pick up the hooks.'
