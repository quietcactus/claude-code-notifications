$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid);
  [DllImport("kernel32.dll")] public static extern bool FreeConsole();

  public static uint Pid(IntPtr h) {
    uint pid;
    GetWindowThreadProcessId(h, out pid);
    return pid;
  }
}
'@

$sessionId = 'default'
try {
  $raw = [Console]::In.ReadToEnd()
  if ($raw) {
    $data = $raw | ConvertFrom-Json
    if ($data.session_id) {
      $sessionId = $data.session_id -replace '[^A-Za-z0-9_-]', ''
    }
  }
} catch { }

$dir = Join-Path $env:TEMP 'claude-code-windows'
$sessionFile = Join-Path $dir "$sessionId.txt"

# ancestor chain of this hook (hook -> claude -> shell -> terminal/editor)
$procs = @{}
Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name | ForEach-Object {
  $procs[[uint32]$_.ProcessId] = $_
}
$ancestors = New-Object System.Collections.Generic.List[uint32]
$p = $procs[[uint32]$PID].ParentProcessId
while ($p -and $procs.ContainsKey([uint32]$p) -and -not $ancestors.Contains([uint32]$p)) {
  if ($procs[[uint32]$p].Name -ne 'explorer.exe') {
    $ancestors.Add([uint32]$p)
  }
  $p = $procs[[uint32]$p].ParentProcessId
}

function Test-Usable([IntPtr]$h) {
  return $h -ne [IntPtr]::Zero -and [Fg]::IsWindow($h) -and [Fg]::IsWindowVisible($h)
}

$hwnd = [IntPtr]::Zero

# Windows Terminal: the pseudo-console window of an ancestor is owned by the exact terminal window
[Fg]::FreeConsole() | Out-Null
foreach ($a in $ancestors) {
  if ([Fg]::AttachConsole($a)) {
    $console = [Fg]::GetConsoleWindow()
    [Fg]::FreeConsole() | Out-Null
    if ($console -ne [IntPtr]::Zero) {
      $owner = [Fg]::GetAncestor($console, 3)
      if ($owner -ne $console -and (Test-Usable $owner)) {
        $hwnd = $owner
      }
      break
    }
  }
}

# editors (Cursor / VS Code): foreground window, only if it belongs to an ancestor process
if ($hwnd -eq [IntPtr]::Zero) {
  $fg = [Fg]::GetForegroundWindow()
  if ((Test-Usable $fg) -and $ancestors.Contains([Fg]::Pid($fg))) {
    $hwnd = $fg
  }
}

# keep the previously recorded window if it still belongs to an ancestor process
if ($hwnd -eq [IntPtr]::Zero -and (Test-Path $sessionFile)) {
  $prev = [int64]0
  if ([int64]::TryParse((Get-Content $sessionFile -Raw).Trim(), [ref]$prev)) {
    $prevHwnd = [IntPtr]$prev
    if ((Test-Usable $prevHwnd) -and $ancestors.Contains([Fg]::Pid($prevHwnd))) {
      exit
    }
  }
}

# fall back to the main window of the nearest ancestor that has one
if ($hwnd -eq [IntPtr]::Zero) {
  foreach ($a in $ancestors) {
    $main = (Get-Process -Id $a).MainWindowHandle
    if (Test-Usable $main) {
      $hwnd = $main
      break
    }
  }
}

if ($hwnd -eq [IntPtr]::Zero) {
  exit
}

$value = [int64]$hwnd
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$value | Out-File -FilePath $sessionFile -Encoding ascii -NoNewline

# legacy single-window file, kept as fallback
$value | Out-File -FilePath (Join-Path $env:TEMP 'claude-code-window.txt') -Encoding ascii -NoNewline
