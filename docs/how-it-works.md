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
