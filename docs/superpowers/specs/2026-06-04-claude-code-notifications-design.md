# claude-code-notifications — Design Spec

**Date:** 2026-06-04
**Status:** Approved, pre-implementation
**Repo:** `F:\repos\claude-code-notifications`

## Summary

A public, install-on-Windows tool that gives Claude Code **clickable Windows toast notifications**. A toast fires when Claude needs input or finishes a task. Clicking the toast snaps focus back to the exact terminal window that launched the Claude session — near-instant (~10–30ms) via a precompiled native exe, avoiding the multi-second lag of runtime-compiled PowerShell.

Target platform: Windows 10/11 with Claude Code installed. No dependencies beyond what ships with Windows (.NET Framework 4 `csc.exe`, PowerShell 5.1).

## Problem

Claude Code on Windows has no built-in clickable notifications. A naive focus implementation (protocol → wscript → PowerShell → `Add-Type` live C# compile → Win32 calls) lags 0.5–2s on click because `Add-Type` invokes `csc.exe` to compile a user32 wrapper on every invocation, plus a wscript→powershell process-spawn chain. This tool eliminates both costs.

## Architecture

Two decoupled halves:

```
Claude Code event
  ├─ UserPromptSubmit ─→ claude-record-window.ps1 ─→ writes foreground HWND to %TEMP%\claude-code-window.txt
  ├─ Notification ──────→ notify-toast.ps1 "Needs your input"
  └─ Stop ──────────────→ notify-toast.ps1 "Done"
                                   │ toast launch attribute = claudefocus:open
        user clicks toast ─────────┘
                                   ▼
        claudefocus: protocol (HKCU) ─→ claudefocus.exe ─→ reads HWND ─→ focus
                                        (single native process, ~10–30ms)
```

- **Notify half:** `notify-toast.ps1` sends a Windows toast (WinRT ToastNotificationManager) with `activationType=protocol`, `launch=claudefocus:open`.
- **Focus half:** `claude-record-window.ps1` records the HWND of the foreground window at prompt-submit time. `claudefocus.exe` (compiled from `claude-focus.cs`) reads that HWND and brings the window forward using restore-if-minimized + `AttachThreadInput` + `BringWindowToTop` + `SetForegroundWindow`.

### Why a compiled exe (core design decision)

The focus logic itself is fast; the latency was entirely in *how it was invoked*. Replacing per-click `Add-Type` compilation and the wscript→powershell chain with one precompiled `winexe` (no console flash) collapses click-to-focus to a single native process launch.

The exe is **compiled at install time** via the `csc.exe` bundled with .NET Framework 4 (present on all Win10/11) — it is **not** committed as a binary. No binary-in-git, no trust concern.

## Components

| File | Role | Depends on |
|------|------|-----------|
| `src/claude-record-window.ps1` | Hook (UserPromptSubmit). Writes foreground HWND to `%TEMP%\claude-code-window.txt`. | PowerShell, user32 GetForegroundWindow |
| `src/notify-toast.ps1` | Hook (Notification, Stop). Sends toast with `-Title`/`-Message` params; launch=`claudefocus:open`. | WinRT toast APIs |
| `src/claude-focus.cs` | Source for `claudefocus.exe`. Reads HWND file, focuses window. | user32, kernel32 |
| `install.ps1` | One-shot installer. | csc.exe, registry, settings.json |
| `uninstall.ps1` | Reverses install, restores settings backup. | — |
| `README.md` | Product doc + quick install + manual steps + troubleshooting + uninstall. | — |
| `docs/how-it-works.md` | Latency story + architecture deep-dive. | — |
| `LICENSE` | MIT. | — |

## install.ps1 flow

```
1. Locate .claude dir  → $env:USERPROFILE\.claude (override via -ClaudeDir param). Abort with clear message if missing.
2. Copy hooks          → src\*.ps1 → <claude>\hooks\
3. Compile exe         → csc.exe /nologo /target:winexe /out:<claude>\hooks\claudefocus.exe src\claude-focus.cs
                         Abort with clear message if claudefocus.exe is locked/running.
4. Register protocol   → HKCU\SOFTWARE\Classes\claudefocus\(default)="URL:claudefocus"
                         + URL Protocol marker
                         + shell\open\command\(default)='"<claude>\hooks\claudefocus.exe"'
                         Paths resolved from step 1 — no hardcoded user paths.
5. Merge settings.json → backup <claude>\settings.json to settings.json.bak-<Get-Date stamp>;
                         parse JSON; add the 3 hooks (Notification, Stop, UserPromptSubmit) only if an
                         equivalent command is not already present (idempotent); write back.
6. Print summary       → list what changed; instruct "restart Claude Code".
```

**uninstall.ps1:** delete copied hooks + `claudefocus.exe`, remove `HKCU\SOFTWARE\Classes\claudefocus`, restore newest `settings.json.bak-*`, report.

### settings.json hook block injected

```jsonc
"UserPromptSubmit": [ { "matcher": "", "hooks": [ { "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"<claude>/hooks/claude-record-window.ps1\"" } ] } ],
"Notification": [ { "matcher": "", "hooks": [ { "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"<claude>/hooks/notify-toast.ps1\" -Title \"Claude Code\" -Message \"Needs your input\"" } ] } ],
"Stop": [ { "matcher": "", "hooks": [ { "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"<claude>/hooks/notify-toast.ps1\" -Title \"Claude Code\" -Message \"Done\"" } ] } ]
```

`<claude>` is replaced with the resolved absolute path at install time. Merge is additive: existing arrays for these keys are appended to (idempotency check on the command string) rather than overwritten.

## Path handling (the public-ification)

Every `C:\Users\ianga` reference from the original personal setup is removed. Runtime scripts already use `%TEMP%` or parameters. Only two places need a real absolute path, both injected at install time from the resolved `.claude` dir: the registry `shell\open\command` value, and the hook command strings in settings.json.

## Error handling

- `.claude` dir not found → abort, tell user to pass `-ClaudeDir`.
- `csc.exe` not found → abort with link to .NET Framework (rare; bundled on Win10/11).
- `claudefocus.exe` locked → abort, tell user to close running instances.
- settings.json parse failure → abort before writing, leave original untouched, point to backup.
- Hooks already present → skip injection (idempotent re-run safe).

## Defaults locked

- Exe compiled on install (not committed as binary).
- License: MIT.
- Toast AUMID stays `powershell.exe` (toasts label "Windows PowerShell"). Custom "Claude Code" AUMID branding deferred to future enhancement (requires Start-menu shortcut registration).

## Out of scope (v1 / YAGNI)

- Custom toast AUMID / branding.
- Cross-platform (macOS/Linux) — Windows only.
- Configurable toast text via env vars (hardcoded "Needs your input" / "Done" in the hook block; user can edit settings.json).
- Multi-terminal session disambiguation beyond last-recorded HWND.

## Testing

- `install.ps1` on a clean `.claude` (no existing hooks) → all 3 hooks added, exe compiles, protocol registers.
- Re-run `install.ps1` → idempotent, no duplicate hooks.
- `install.ps1` where Notification/Stop already exist → appends without clobbering.
- Click toast → focus snaps to recorded terminal, no console flash.
- `uninstall.ps1` → settings restored from backup, exe + registry gone.
