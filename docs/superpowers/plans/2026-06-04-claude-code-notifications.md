# claude-code-notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a public Windows tool that gives Claude Code clickable toast notifications which snap focus back to the launching terminal near-instantly.

**Architecture:** Two decoupled halves — a notify half (PowerShell toast sender + window recorder hooks) and a focus half (a `claudefocus:` protocol handler backed by a precompiled native exe). An `install.ps1` resolves the user's `.claude` dir, copies hooks, compiles the exe with the built-in `csc.exe`, registers the protocol, and idempotently merges three hooks into `settings.json` with a backup.

**Tech Stack:** Windows PowerShell 5.1, .NET Framework 4 `csc.exe`, WinRT toast APIs, Win32 user32, HKCU registry, Pester (tests for merge logic).

---

## File Structure

```
claude-code-notifications/
├─ README.md
├─ LICENSE                 # MIT
├─ .gitattributes          # pin LF for *.ps1 *.cs *.md
├─ install.ps1
├─ uninstall.ps1
├─ src/
│  ├─ claude-focus.cs
│  ├─ notify-toast.ps1
│  └─ claude-record-window.ps1
├─ tests/
│  └─ Merge-Hooks.Tests.ps1   # Pester tests for settings.json merge logic
└─ docs/
   ├─ how-it-works.md
   ├─ superpowers/specs/2026-06-04-claude-code-notifications-design.md   # already committed
   └─ superpowers/plans/2026-06-04-claude-code-notifications.md          # this file
```

The settings.json merge logic is factored into a standalone function `Merge-ClaudeHooks` in `install.ps1` (dot-sourceable) so it can be unit-tested by Pester without touching the real registry or compiling anything. Everything else is verified by concrete manual steps.

---

## Task 1: Repo hygiene files (.gitattributes, LICENSE)

**Files:**
- Create: `.gitattributes`
- Create: `LICENSE`

- [ ] **Step 1: Create `.gitattributes`**

```gitattributes
* text=auto eol=lf
*.ps1 text eol=lf
*.cs  text eol=lf
*.md  text eol=lf
*.exe binary
```

- [ ] **Step 2: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 <REPLACE WITH YOUR NAME>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> Note: the user must replace `<REPLACE WITH YOUR NAME>`. Flag this in the final summary; do not invent a name.

- [ ] **Step 3: Commit**

```bash
git add .gitattributes LICENSE
git commit -m "chore: add gitattributes and MIT license"
```

---

## Task 2: Window recorder hook (`src/claude-record-window.ps1`)

**Files:**
- Create: `src/claude-record-window.ps1`

- [ ] **Step 1: Write the script**

```powershell
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
'@

$hwnd = [Fg]::GetForegroundWindow()
$file = Join-Path $env:TEMP 'claude-code-window.txt'
[int64]$hwnd | Out-File -FilePath $file -Encoding ascii -NoNewline
```

- [ ] **Step 2: Verify it records a handle**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\claude-record-window.ps1; Get-Content "$env:TEMP\claude-code-window.txt"`
Expected: a non-empty integer printed (the foreground HWND). Not `0`.

- [ ] **Step 3: Commit**

```bash
git add src/claude-record-window.ps1
git commit -m "feat: add foreground window recorder hook"
```

---

## Task 3: Toast sender hook (`src/notify-toast.ps1`)

**Files:**
- Create: `src/notify-toast.ps1`

- [ ] **Step 1: Write the script**

```powershell
param(
  [string]$Title = 'Claude Code',
  [string]$Message = 'Notification'
)

$ErrorActionPreference = 'SilentlyContinue'

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

# AUMID of the built-in Windows PowerShell shortcut. Toasts render under "Windows PowerShell".
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$nodes = $template.GetElementsByTagName('text')
$nodes.Item(0).AppendChild($template.CreateTextNode($Title)) | Out-Null
$nodes.Item(1).AppendChild($template.CreateTextNode($Message)) | Out-Null

$toastNode = $template.SelectSingleNode('/toast')
$toastNode.SetAttribute('activationType', 'protocol') | Out-Null
$toastNode.SetAttribute('launch', 'claudefocus:open') | Out-Null

$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
```

- [ ] **Step 2: Verify a toast appears**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File src\notify-toast.ps1 -Title "Claude Code" -Message "Test"`
Expected: a Windows toast appears top-right reading "Claude Code / Test". (Clicking does nothing yet — protocol not registered until install.)

- [ ] **Step 3: Commit**

```bash
git add src/notify-toast.ps1
git commit -m "feat: add toast notification sender hook"
```

---

## Task 4: Focus exe source (`src/claude-focus.cs`)

**Files:**
- Create: `src/claude-focus.cs`

- [ ] **Step 1: Write the C# source**

```csharp
using System;
using System.IO;
using System.Runtime.InteropServices;

class ClaudeFocus {
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);

  [STAThread]
  static void Main() {
    try {
      string file = Path.Combine(Environment.GetEnvironmentVariable("TEMP"), "claude-code-window.txt");
      if (!File.Exists(file)) { return; }
      long raw;
      if (!long.TryParse(File.ReadAllText(file).Trim(), out raw)) { return; }
      IntPtr hwnd = new IntPtr(raw);
      if (hwnd == IntPtr.Zero) { return; }

      if (IsIconic(hwnd)) { ShowWindow(hwnd, 9); } // 9 = SW_RESTORE

      uint fgThread = GetWindowThreadProcessId(hwnd, IntPtr.Zero);
      uint curThread = GetCurrentThreadId();
      AttachThreadInput(curThread, fgThread, true);
      BringWindowToTop(hwnd);
      SetForegroundWindow(hwnd);
      AttachThreadInput(curThread, fgThread, false);
    } catch { }
  }
}
```

- [ ] **Step 2: Verify it compiles and runs**

Run:
```
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /out:"$env:TEMP\claudefocus-test.exe" src\claude-focus.cs
& "$env:TEMP\claudefocus-test.exe"
```
Expected: csc exits 0, `claudefocus-test.exe` produced, running it does not error (it focuses whatever HWND is recorded, or no-ops if the file is absent). Delete the test exe afterward: `Remove-Item "$env:TEMP\claudefocus-test.exe"`.

- [ ] **Step 3: Commit**

```bash
git add src/claude-focus.cs
git commit -m "feat: add precompiled focus exe source"
```

---

## Task 5: Settings merge logic + Pester tests

This is the only piece with real branching logic, so it gets unit tests. The function lives in `install.ps1` but is written test-first here and dot-sourced by the test.

**Files:**
- Create: `install.ps1` (partial — just the function for now)
- Create: `tests/Merge-Hooks.Tests.ps1`

- [ ] **Step 1: Write the failing Pester test**

`tests/Merge-Hooks.Tests.ps1`:

```powershell
. "$PSScriptRoot\..\install.ps1" -DotSourceOnly

Describe 'Merge-ClaudeHooks' {
  It 'adds all three hook keys to an empty settings object' {
    $settings = @{}
    $result = Merge-ClaudeHooks -Settings $settings -ClaudeDir 'C:/x/.claude'
    $result.hooks.Notification     | Should -Not -BeNullOrEmpty
    $result.hooks.Stop             | Should -Not -BeNullOrEmpty
    $result.hooks.UserPromptSubmit | Should -Not -BeNullOrEmpty
  }

  It 'is idempotent — second merge adds no duplicates' {
    $settings = @{}
    $once  = Merge-ClaudeHooks -Settings $settings -ClaudeDir 'C:/x/.claude'
    $twice = Merge-ClaudeHooks -Settings $once     -ClaudeDir 'C:/x/.claude'
    $twice.hooks.Notification.Count | Should -Be 1
  }

  It 'preserves an existing unrelated hook entry under the same key' {
    $settings = @{ hooks = @{ Notification = @( @{ matcher=''; hooks=@( @{ type='command'; command='echo other' } ) } ) } }
    $result = Merge-ClaudeHooks -Settings $settings -ClaudeDir 'C:/x/.claude'
    ($result.hooks.Notification | Measure-Object).Count | Should -Be 2
  }

  It 'embeds the resolved ClaudeDir in the command path' {
    $result = Merge-ClaudeHooks -Settings @{} -ClaudeDir 'C:/custom/.claude'
    $result.hooks.UserPromptSubmit[0].hooks[0].command | Should -Match 'C:/custom/.claude/hooks/claude-record-window.ps1'
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester tests\Merge-Hooks.Tests.ps1`
Expected: FAIL — `install.ps1` does not exist / `Merge-ClaudeHooks` not defined.

- [ ] **Step 3: Write `install.ps1` with the function and a `-DotSourceOnly` guard**

```powershell
[CmdletBinding()]
param(
  [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude'),
  [switch]$DotSourceOnly
)

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

# ---- main install flow (Tasks 6) appended below ----
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester tests\Merge-Hooks.Tests.ps1`
Expected: PASS — all 4 tests green.

> If Pester is not installed: `Install-Module Pester -Scope CurrentUser -Force`. Note this in README dev section.

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Merge-Hooks.Tests.ps1
git commit -m "feat: add idempotent settings.json hook merge with tests"
```

---

## Task 6: install.ps1 main flow

**Files:**
- Modify: `install.ps1` (replace the trailing comment with the full flow)

- [ ] **Step 1: Replace the trailing comment line with the install flow**

Replace `# ---- main install flow (Tasks 6) appended below ----` with:

```powershell
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
```

> `ConvertFrom-Json -AsHashtable` requires PowerShell 5.1+ (`-AsHashtable` added in 6.0 actually — see Step 2 note).

- [ ] **Step 2: Resolve the `-AsHashtable` version caveat**

`-AsHashtable` on `ConvertFrom-Json` is PowerShell 6+. To support Windows PowerShell 5.1, the installer must run under `pwsh` OR convert PSCustomObject to hashtable manually. Decision: **require PowerShell 7+ (`pwsh`) for install** (already present on target per environment) and document it. Add at top of `install.ps1`, right after `param(...)`:

```powershell
if ($PSVersionTable.PSVersion.Major -lt 6 -and -not $DotSourceOnly) {
  throw "install.ps1 requires PowerShell 7+. Run with 'pwsh -File install.ps1'."
}
```

- [ ] **Step 3: Dry-run the installer against a throwaway .claude**

Run:
```
$tmp = Join-Path $env:TEMP 'cctest-claude'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
'{ "model": "opus" }' | Out-File (Join-Path $tmp 'settings.json') -Encoding utf8
pwsh -File install.ps1 -ClaudeDir $tmp
```
Expected: hooks copied, `claudefocus.exe` compiled under `$tmp\hooks`, protocol registered, `settings.json` now contains Notification/Stop/UserPromptSubmit plus the original `model` key, and a `settings.json.bak-*` exists.

- [ ] **Step 4: Verify idempotency on the throwaway**

Run: `pwsh -File install.ps1 -ClaudeDir $tmp`
Then inspect: `(Get-Content (Join-Path $tmp 'settings.json') -Raw | ConvertFrom-Json).hooks.Notification.Count`
Expected: `1` (no duplicate). A second `.bak` file is created — acceptable.

- [ ] **Step 5: Re-run the Pester suite (regression)**

Run: `Invoke-Pester tests\Merge-Hooks.Tests.ps1`
Expected: PASS — the merge function still behaves (Step 1 edits didn't break it).

- [ ] **Step 6: Commit**

```bash
git add install.ps1
git commit -m "feat: add install.ps1 main flow (copy, compile, register, merge)"
```

---

## Task 7: uninstall.ps1

**Files:**
- Create: `uninstall.ps1`

- [ ] **Step 1: Write the script**

```powershell
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
```

- [ ] **Step 2: Verify against the throwaway from Task 6**

Run: `pwsh -File uninstall.ps1 -ClaudeDir (Join-Path $env:TEMP 'cctest-claude')`
Then: `Test-Path "HKCU:\SOFTWARE\Classes\claudefocus"` and check `$tmp\hooks` is empty of the 3 files, and settings.json matches a backup.
Expected: protocol gone, files removed, settings restored. Clean up: `Remove-Item (Join-Path $env:TEMP 'cctest-claude') -Recurse -Force`.

- [ ] **Step 3: Commit**

```bash
git add uninstall.ps1
git commit -m "feat: add uninstall.ps1"
```

---

## Task 8: README + how-it-works docs

**Files:**
- Create: `README.md`
- Create: `docs/how-it-works.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# claude-code-notifications

Clickable Windows toast notifications for [Claude Code](https://claude.com/claude-code).
A toast pops when Claude needs your input or finishes a task. **Click it and focus
snaps back to the exact terminal that launched the session** — in ~10–30ms, not the
multi-second lag of naive PowerShell focus hooks.

## Requirements

- Windows 10/11
- Claude Code installed (a `.claude` directory in your user profile)
- PowerShell 7+ (`pwsh`) to run the installer
- .NET Framework 4.x (`csc.exe`) — bundled with Windows; used once at install to compile the focus helper

## Install

```powershell
git clone https://github.com/<you>/claude-code-notifications
cd claude-code-notifications
pwsh -File install.ps1
```

Then restart Claude Code.

Custom `.claude` location:

```powershell
pwsh -File install.ps1 -ClaudeDir "D:\path\to\.claude"
```

The installer:
1. copies two hook scripts into `<.claude>\hooks\`,
2. compiles `claudefocus.exe` into `<.claude>\hooks\` using the built-in `csc.exe`,
3. registers a `claudefocus:` URL protocol in `HKCU`,
4. backs up `settings.json` and idempotently adds three hooks (`Notification`, `Stop`, `UserPromptSubmit`).

## How it works

`UserPromptSubmit` records the foreground window's handle to `%TEMP%`. The toast carries
`launch=claudefocus:open`; clicking it invokes the `claudefocus:` protocol, which runs the
precompiled `claudefocus.exe` directly — one native process that reads the handle and brings
the window forward. No runtime C# compilation, no wscript→powershell chain. See
[docs/how-it-works.md](docs/how-it-works.md).

## Uninstall

```powershell
pwsh -File uninstall.ps1
```

Removes the hooks and exe, unregisters the protocol, and restores the newest `settings.json` backup.

## Customizing the toast text

The notification strings live in the hook commands in `settings.json`
(`-Message "Needs your input"` / `-Message "Done"`). Edit them there.

## Development

Run the merge-logic tests:

```powershell
Install-Module Pester -Scope CurrentUser -Force   # if needed
Invoke-Pester tests\Merge-Hooks.Tests.ps1
```

## License

MIT — see [LICENSE](LICENSE).
````

- [ ] **Step 2: Write `docs/how-it-works.md`**

````markdown
# How it works

## The two halves

**Notify.** `notify-toast.ps1` builds a WinRT `ToastText02` toast and shows it under the
Windows PowerShell AppUserModelID. The toast sets `activationType=protocol` and
`launch=claudefocus:open`, so clicking it asks Windows to open the `claudefocus:` URL.

**Focus.** `claude-record-window.ps1` runs on every `UserPromptSubmit` and writes the
foreground window handle (HWND) to `%TEMP%\claude-code-window.txt`. When the toast is
clicked, the `claudefocus:` protocol handler launches `claudefocus.exe`, which reads that
HWND and focuses the window via `AttachThreadInput` + `BringWindowToTop` +
`SetForegroundWindow` (restoring it first if minimized).

## Why the exe — the latency story

A naive focus handler chains `protocol → wscript → powershell → Add-Type → Win32`. The
`Add-Type` call compiles a C# user32 wrapper **at runtime on every click**, invoking
`csc.exe` — 0.5–2s cold — on top of a wscript→powershell spawn chain. That is the entire
perceptible lag.

Precompiling the same logic once (at install) into a `winexe` (no console-window flash) and
pointing the protocol straight at it collapses click-to-focus to a single native process
launch: roughly 10–30ms. The focus logic was never the bottleneck — the invocation was.

## Files installed

| File | Location | Trigger |
|------|----------|---------|
| `claude-record-window.ps1` | `<.claude>\hooks\` | UserPromptSubmit hook |
| `notify-toast.ps1` | `<.claude>\hooks\` | Notification + Stop hooks |
| `claudefocus.exe` | `<.claude>\hooks\` | `claudefocus:` protocol (HKCU) |
````

- [ ] **Step 3: Commit**

```bash
git add README.md docs/how-it-works.md
git commit -m "docs: add README and how-it-works"
```

---

## Task 9: Final end-to-end verification on the real .claude

> This task installs onto the developer's actual Claude Code. Do it knowingly; a `settings.json` backup is created automatically.

- [ ] **Step 1: Install for real**

Run: `pwsh -File install.ps1`
Expected: success summary, `settings.json.bak-*` created.

- [ ] **Step 2: Confirm hooks present**

Inspect `<.claude>\settings.json` — Notification, Stop, UserPromptSubmit each contain a command pointing at the installed hook paths. Confirm a `claudefocus.exe` exists in `<.claude>\hooks\`.

- [ ] **Step 3: Live click test**

Restart Claude Code. Submit a prompt (records the window). Switch focus to another app. When a toast appears (input-needed or done), click it.
Expected: focus snaps back to the Claude terminal near-instantly, no console window flashes.

- [ ] **Step 4: Confirm no regression in existing hooks**

Verify Claude Code's other hooks (statusline, any gsd hooks) still function — the merge is additive and should not have touched them.

- [ ] **Step 5: Tag a release**

```bash
git tag -a v1.0.0 -m "v1.0.0 — clickable Windows toast notifications for Claude Code"
```

---

## Self-Review

**Spec coverage:** notify half (Tasks 3) ✓, focus half (Tasks 2,4) ✓, install flow steps 1–6 (Tasks 5,6) ✓, uninstall (Task 7) ✓, path public-ification (Task 6 merge uses `$ClaudeDir`, registry uses `$exePath`) ✓, error handling (Task 6 throws) ✓, README + how-it-works (Task 8) ✓, MIT + .gitattributes (Task 1) ✓, testing strategy (Task 5 Pester + manual) ✓. No gaps.

**Placeholder scan:** LICENSE name is an intentional user-supplied value, flagged in Task 1. No TBD/TODO elsewhere.

**Type/name consistency:** `Merge-ClaudeHooks -Settings -ClaudeDir` signature identical across Task 5 (definition + tests) and Task 6 (call). `claudefocus.exe`, `claude-code-window.txt`, `claudefocus:open`, AUMID string consistent across all tasks and matches the spec.

**Known caveat surfaced:** `-AsHashtable` forces PowerShell 7+ for install (Task 6 Step 2) — documented in README requirements.
