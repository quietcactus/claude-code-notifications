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

# ---- main install flow (Task 6) appended below ----
