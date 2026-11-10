param(
  [string]$Title = 'Claude Code',
  [string]$Message = 'Notification'
)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinInfo {
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
}
'@

function Get-Snippet([string]$text, [int]$max) {
  if (-not $text) {
    return ''
  }
  $clean = ($text -replace '[`*#>_]', '' -replace '\s+', ' ').Trim()
  if ($clean.Length -gt $max) {
    $clean = $clean.Substring(0, $max - 1).TrimEnd() + [char]0x2026
  }
  return $clean
}

$data = $null
try {
  $stdin = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
  $raw = $stdin.ReadToEnd()
  if ($raw) {
    $data = $raw | ConvertFrom-Json
  }
} catch { }

$sessionId = 'default'
$project = ''
$event = ''
$detail = ''

if ($data) {
  if ($data.session_id) {
    $sessionId = $data.session_id -replace '[^A-Za-z0-9_-]', ''
  }
  if ($data.cwd) {
    $project = Split-Path $data.cwd -Leaf
  }
  $event = $data.hook_event_name

  if ($event -eq 'Notification' -and $data.message) {
    $Message = $data.message
  }

  if ($event -eq 'Stop') {
    $last = $data.last_assistant_message
    if (-not $last -and $data.transcript_path -and (Test-Path $data.transcript_path)) {
      $lines = Get-Content $data.transcript_path -Tail 50 -Encoding UTF8
      for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        try {
          $entry = $lines[$i] | ConvertFrom-Json
        } catch {
          continue
        }
        if ($entry.type -eq 'assistant' -and $entry.message.content) {
          $texts = @($entry.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text })
          if ($texts.Count -gt 0) {
            $last = $texts -join ' '
            break
          }
        }
      }
    }
    $detail = Get-Snippet $last 140
  }
}

$hwnd = [int64]0
$sessionFile = Join-Path (Join-Path $env:TEMP 'claude-code-windows') "$sessionId.txt"
$legacyFile = Join-Path $env:TEMP 'claude-code-window.txt'
foreach ($f in @($sessionFile, $legacyFile)) {
  if (Test-Path $f) {
    $val = [int64]0
    if ([int64]::TryParse((Get-Content $f -Raw).Trim(), [ref]$val) -and [WinInfo]::IsWindow([IntPtr]$val)) {
      $hwnd = $val
      break
    }
  }
}

$heading = $Title
if ($project) {
  $heading = "$Title " + [char]0x2014 + " $project"
}

$body = $Message
if ($detail) {
  $body = "$Message" + ': ' + $detail
}

function Esc([string]$s) {
  return [Security.SecurityElement]::Escape($s)
}

$launch = 'claudefocus:open'
if ($hwnd -ne 0) {
  $launch = "claudefocus:$hwnd"
}

$xml = @"
<toast activationType="protocol" launch="$(Esc $launch)">
  <visual>
    <binding template="ToastGeneric">
      <text hint-maxLines="1">$(Esc $heading)</text>
      <text>$(Esc $body)</text>
    </binding>
  </visual>
  <actions>
    <action content="Focus window" activationType="protocol" arguments="$(Esc $launch)" />
    <action content="Dismiss" activationType="system" arguments="dismiss" />
  </actions>
</toast>
"@

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
$doc.LoadXml($xml)

$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
$toast.Tag = $sessionId.Substring(0, [Math]::Min(16, $sessionId.Length))
$toast.Group = 'claude-code'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
