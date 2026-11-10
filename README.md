# claude-code-notifications

Clickable Windows toast notifications for [Claude Code](https://claude.com/claude-code).

A toast pops when Claude finishes a response or needs your input. It shows the project
folder and a snippet of Claude's reply. **Click it (or "Focus window") and the exact
window that launched that session comes to the front**, even with several Claude sessions
open at once.

## Why

Built for the multi-IDE workflow: several editors or terminals open, one per codebase,
each running its own Claude Code session. When a session pings you, the toast tells you
*which* one, and a single click drops you into the right window. No Alt-Tab archaeology.

The window is resolved from the Claude process itself (Windows Terminal, Cursor, VS Code),
so switching apps right after sending a prompt does not record the wrong one. Maximized
windows stay maximized when focused.

## Requirements

- Windows 10/11
- Claude Code installed
- Nothing else to download. The small focus helper (`claudefocus.exe`) is compiled on your
  machine with the .NET Framework 4 compiler that ships with Windows.

## Install

Double-click `Install.cmd`, or from a terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Then restart any open Claude Code sessions.

Custom `.claude` location (the installer also honors `CLAUDE_CONFIG_DIR`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ClaudeDir "D:\path\to\.claude"
```

What install does:

1. copies the `payload\` scripts to `<.claude>\hooks\claude-notify\`,
2. compiles `claudefocus.exe` there with the built-in `csc.exe`,
3. registers the `claudefocus:` URL protocol for the current user (HKCU),
4. backs up `settings.json`, then adds `UserPromptSubmit`, `Stop` and `Notification` hooks.
   Existing notification hooks from this project are replaced; other hooks are left alone.

Re-running install is safe.

## Uninstall

Double-click `Uninstall.cmd`, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
```

Reverses everything install did: removes the hooks from `settings.json` (backed up
first), unregisters the protocol, deletes the install directory and the per-session
window files in `%TEMP%`.

## How it works

`UserPromptSubmit` walks the hook's process ancestry to find the terminal or editor window
that owns the Claude session and records its handle per session. The toast carries
`claudefocus:<hwnd>`; clicking it runs the precompiled `claudefocus.exe`, which brings that
window forward. See [docs/how-it-works.md](docs/how-it-works.md).

## Customizing the toast text

The default strings live in the hook commands in `settings.json`
(`-Message "Done"` / `-Message "Needs your input"`). Edit them there. `Notification`
events use Claude's own message when one is provided.

## Development

Run the settings merge tests (Pester 5):

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester tests
```

## License

MIT. See [LICENSE](LICENSE).
