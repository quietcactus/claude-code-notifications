# How it works

## Three pieces

**Record.** `claude-record-window.ps1` runs on every `UserPromptSubmit`. It reads the hook
JSON from stdin for the `session_id`, then finds the window that owns this Claude session
and writes its handle (HWND) to `%TEMP%\claude-code-windows\<session_id>.txt`.

**Notify.** `notify-toast.ps1` runs on `Stop` and `Notification`. It reads the hook JSON
for the session id, project folder (`cwd` leaf) and, on `Stop`, the last assistant message
(from `last_assistant_message`, or the tail of the transcript as fallback). It builds a
WinRT `ToastGeneric` toast with `activationType="protocol"` and `launch="claudefocus:<hwnd>"`,
tagged by session so repeated toasts for one session replace each other.

**Focus.** Clicking the toast opens the `claudefocus:` URL. The HKCU protocol handler runs
`claudefocus.exe <url>`, which parses the HWND and brings the window forward.

## Finding the right window

The hook process is a descendant of the terminal or editor that hosts Claude:
`hook -> claude -> shell -> Windows Terminal / Cursor / VS Code`. The recorder collects
that ancestor chain (skipping `explorer.exe`) and tries, in order:

1. **Windows Terminal.** `AttachConsole` to each ancestor; the pseudo-console window's
   owner (`GetAncestor(GA_ROOTOWNER)`) is the exact terminal window, even with many tabs
   and windows open.
2. **Editors.** The current foreground window, but only if its process is in the ancestor
   chain. This catches Cursor and VS Code integrated terminals.
3. **Keep previous.** If a window was already recorded for this session and still belongs
   to an ancestor, leave it alone.
4. **Fallback.** The `MainWindowHandle` of the nearest ancestor that has one.

Because the window is resolved from process ancestry instead of "whatever is in front",
switching apps right after sending a prompt does not record the wrong window.

## Focusing reliably

Windows refuses `SetForegroundWindow` from a process the user did not interact with.
`claudefocus.exe` works around that:

- `AllowSetForegroundWindow(-1)` and a simulated Alt tap release the foreground lock.
- `AttachThreadInput` joins the helper's thread to both the current foreground thread and
  the target window's thread.
- `SetWindowPos` topmost then not-topmost, `BringWindowToTop`, `SetForegroundWindow`.
- Up to 10 attempts 60ms apart, then `SwitchToThisWindow` as a last resort.

A minimized window is restored with `ShowWindow`, using `WINDOWPLACEMENT` to return to
maximized when that was its prior state. A window that is not minimized is left as is, so
maximized and fullscreen windows keep their size.

## Why a compiled exe

A naive handler chains `protocol -> wscript -> powershell -> Add-Type -> Win32` and
compiles C# at runtime on every click, which is the entire perceptible lag. The installer
compiles `claudefocus.exe` once with the .NET Framework `csc.exe` that ships with Windows,
so a click is a single native process start.

## settings.json merge

`common.ps1` owns the merge. Hooks are identified by the script names they invoke
(`notify-toast.ps1`, `claude-record-window.ps1`). Install removes any hook entries
matching those markers, then appends fresh ones; everything else in `settings.json` is
preserved. Uninstall removes the same markers and drops `hooks` entirely if nothing is
left. Both back up the file before writing.
