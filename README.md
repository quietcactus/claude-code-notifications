# claude-code-notifications

Clickable Windows toast notifications for [Claude Code](https://claude.com/claude-code).
A toast pops when Claude needs your input or finishes a task. **Click it and focus
snaps straight to the exact terminal that launched that session** — in ~10–30ms, not the
multi-second lag of naive PowerShell focus hooks.

## Why

Built for the multi-IDE workflow: several editors open at once, one per codebase, each
running its own Claude Code session. When a session needs input or wraps up, you don't want
to hunt through a stack of near-identical windows to find which one. The toast tells you
*which* session pinged you, and a single click drops you into the right terminal — every
session reachable in one click, no Alt-Tab archaeology.

## Requirements

- Windows 10/11
- Claude Code installed (a `.claude` directory in your user profile)
- PowerShell 7+ (`pwsh`) to run the installer
- .NET Framework 4.x (`csc.exe`) — bundled with Windows; used once at install to compile the focus helper

## Install

```powershell
git clone https://github.com/quietcactus/claude-code-notifications
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

Removes the hooks and exe, unregisters the protocol, and restores the newest `settings.json`
backup. Note: if you ran `install.ps1` multiple times, the newest backup is the state *before
the last install* — which may already contain the hooks. For a fully clean removal after
repeated installs, restore an earlier `settings.json.bak-*` or remove the three hook entries
by hand.

## Customizing the toast text

The notification strings live in the hook commands in `settings.json`
(`-Message "Needs your input"` / `-Message "Done"`). Edit them there.

## Development

Run the merge-logic tests (Pester 5):

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester tests\Merge-Hooks.Tests.ps1
```

## License

MIT — see [LICENSE](LICENSE).
