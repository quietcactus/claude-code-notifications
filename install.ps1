[CmdletBinding()]
param(
  [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude'),
  [switch]$DotSourceOnly
)

if ($PSVersionTable.PSVersion.Major -lt 6 -and -not $DotSourceOnly) {
  throw "install.ps1 requires PowerShell 7+. Run with 'pwsh -File install.ps1'."
}

$ErrorActionPreference = 'Stop'

function Merge-ClaudeHooks {
  param(
    [Parameter(Mandatory)] $Settings,
    [Parameter(Mandatory)] [string]$ClaudeDir
  )
  # Normalize to a hashtable we can mutate
  $s = $Settings
  if ($null -eq $s) { $s = @{} }
  if (-not $s.ContainsKey('hooks') -or $null -eq $s.hooks) { $s.hooks = @{} }

  $ps = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File'
  $rec = "$ps `"$ClaudeDir/hooks/claude-record-window.ps1`""
  $toastInput = "$ps `"$ClaudeDir/hooks/notify-toast.ps1`" -Title `"Claude Code`" -Message `"Needs your input`""
  $toastDone  = "$ps `"$ClaudeDir/hooks/notify-toast.ps1`" -Title `"Claude Code`" -Message `"Done`""

  $entries = @{
    UserPromptSubmit = $rec
    Notification     = $toastInput
    Stop             = $toastDone
  }

  foreach ($key in $entries.Keys) {
    $cmd = $entries[$key]
    if (-not $s.hooks.ContainsKey($key) -or $null -eq $s.hooks[$key]) {
      $s.hooks[$key] = @()
    }
    # idempotency: skip if a hook with this exact command already exists
    $exists = $false
    foreach ($block in @($s.hooks[$key])) {
      foreach ($h in @($block.hooks)) {
        if ($h.command -eq $cmd) { $exists = $true }
      }
    }
    if (-not $exists) {
      $s.hooks[$key] = @($s.hooks[$key]) + @(
        @{ matcher = ''; hooks = @( @{ type = 'command'; command = $cmd } ) }
      )
    }
  }
  return $s
}

if ($DotSourceOnly) { return }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Locate .claude
if (-not (Test-Path $ClaudeDir)) {
  throw ".claude directory not found at '$ClaudeDir'. Pass -ClaudeDir <path>."
}
$hooksDir = Join-Path $ClaudeDir 'hooks'
if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir | Out-Null }

# 2. Copy hook scripts
Copy-Item (Join-Path $here 'src\claude-record-window.ps1') $hooksDir -Force
Copy-Item (Join-Path $here 'src\notify-toast.ps1')         $hooksDir -Force
Write-Host "Copied hook scripts to $hooksDir"

# 3. Compile the focus exe
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe not found. Install .NET Framework 4.x." }
$exePath = Join-Path $hooksDir 'claudefocus.exe'
try {
  & $csc /nologo /target:winexe /out:"$exePath" (Join-Path $here 'src\claude-focus.cs')
} catch {
  throw "Compile failed. If claudefocus.exe is running, close it and re-run. $_"
}
if ($LASTEXITCODE -ne 0) { throw "csc.exe exited $LASTEXITCODE" }
Write-Host "Compiled $exePath"

# 4. Register claudefocus protocol (HKCU)
$base = 'HKCU:\SOFTWARE\Classes\claudefocus'
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name '(default)' -Value 'URL:claudefocus'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
$cmdKey = Join-Path $base 'shell\open\command'
New-Item -Path $cmdKey -Force | Out-Null
Set-ItemProperty -Path $cmdKey -Name '(default)' -Value ('"{0}"' -f $exePath)
Write-Host "Registered claudefocus: protocol -> $exePath"

# 5. Merge settings.json (with backup)
$settingsPath = Join-Path $ClaudeDir 'settings.json'
if (Test-Path $settingsPath) {
  $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
  $backup = "$settingsPath.bak-$stamp"
  Copy-Item $settingsPath $backup -Force
  Write-Host "Backed up settings.json -> $backup"
  $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else {
  $settings = @{}
}
$merged = Merge-ClaudeHooks -Settings $settings -ClaudeDir ($ClaudeDir -replace '\\','/')
$merged | ConvertTo-Json -Depth 20 | Out-File -FilePath $settingsPath -Encoding utf8
Write-Host "Updated $settingsPath"

# 6. Summary
Write-Host ""
Write-Host "Done. Restart Claude Code for the hooks to take effect." -ForegroundColor Green
