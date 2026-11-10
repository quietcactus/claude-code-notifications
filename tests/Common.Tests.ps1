BeforeAll {
  . "$PSScriptRoot\..\common.ps1"

  function New-Settings([string]$json) {
    return $json | ConvertFrom-Json
  }

  function Get-Commands($settings, [string]$evt) {
    if (-not $settings.PSObject.Properties['hooks'] -or -not $settings.hooks.PSObject.Properties[$evt]) {
      return @()
    }
    return @($settings.hooks.$evt | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
  }
}

Describe 'Get-ClaudeDir' {
  It 'prefers the explicit override' {
    Get-ClaudeDir 'D:\x\.claude' | Should -Be 'D:\x\.claude'
  }

  It 'falls back to CLAUDE_CONFIG_DIR' {
    $old = $env:CLAUDE_CONFIG_DIR
    try {
      $env:CLAUDE_CONFIG_DIR = 'E:\cfg'
      Get-ClaudeDir '' | Should -Be 'E:\cfg'
    } finally {
      $env:CLAUDE_CONFIG_DIR = $old
    }
  }

  It 'defaults to USERPROFILE\.claude' {
    $old = $env:CLAUDE_CONFIG_DIR
    try {
      $env:CLAUDE_CONFIG_DIR = $null
      Get-ClaudeDir '' | Should -Be (Join-Path $env:USERPROFILE '.claude')
    } finally {
      $env:CLAUDE_CONFIG_DIR = $old
    }
  }
}

Describe 'Add-NotifyHook' {
  It 'adds hooks to an empty settings object' {
    $s = New-Settings '{}'
    Add-NotifyHook $s 'Stop' 'x notify-toast.ps1'
    (Get-Commands $s 'Stop') | Should -Be @('x notify-toast.ps1')
  }

  It 'appends to an existing event without touching other entries' {
    $s = New-Settings '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo other"}]}]}}'
    Add-NotifyHook $s 'Stop' 'x notify-toast.ps1'
    (Get-Commands $s 'Stop') | Should -Be @('echo other', 'x notify-toast.ps1')
  }

  It 'uses an empty matcher and command type' {
    $s = New-Settings '{}'
    Add-NotifyHook $s 'Notification' 'x notify-toast.ps1'
    $s.hooks.Notification[0].matcher | Should -Be ''
    $s.hooks.Notification[0].hooks[0].type | Should -Be 'command'
  }
}

Describe 'Remove-NotifyHooks' {
  It 'returns 0 and leaves settings alone when there are no hooks' {
    $s = New-Settings '{"model":"opus"}'
    Remove-NotifyHooks $s | Should -Be 0
    $s.model | Should -Be 'opus'
    $s.PSObject.Properties['hooks'] | Should -BeNullOrEmpty
  }

  It 'removes only hooks matching the markers' {
    $s = New-Settings '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"echo other"},{"type":"command","command":"pwsh notify-toast.ps1"}]}]}}'
    Remove-NotifyHooks $s | Should -Be 1
    (Get-Commands $s 'Stop') | Should -Be @('echo other')
  }

  It 'drops an event whose groups are all removed' {
    $s = New-Settings '{"hooks":{"UserPromptSubmit":[{"matcher":"","hooks":[{"type":"command","command":"pwsh claude-record-window.ps1"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"lint"}]}]}}'
    Remove-NotifyHooks $s | Should -Be 1
    $s.hooks.PSObject.Properties['UserPromptSubmit'] | Should -BeNullOrEmpty
    (Get-Commands $s 'PreToolUse') | Should -Be @('lint')
  }

  It 'drops the hooks key entirely when nothing is left' {
    $s = New-Settings '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"pwsh notify-toast.ps1"}]}]}}'
    Remove-NotifyHooks $s | Should -Be 1
    $s.PSObject.Properties['hooks'] | Should -BeNullOrEmpty
  }

  It 'makes install idempotent: remove then add yields one hook per event' {
    $s = New-Settings '{}'
    foreach ($i in 1..3) {
      Remove-NotifyHooks $s | Out-Null
      Add-NotifyHook $s 'Stop' 'x notify-toast.ps1'
      Add-NotifyHook $s 'Notification' 'x notify-toast.ps1'
      Add-NotifyHook $s 'UserPromptSubmit' 'x claude-record-window.ps1'
    }
    (Get-Commands $s 'Stop').Count | Should -Be 1
    (Get-Commands $s 'Notification').Count | Should -Be 1
    (Get-Commands $s 'UserPromptSubmit').Count | Should -Be 1
  }
}

Describe 'Write-Settings / Read-Settings round trip' {
  BeforeEach {
    $script:tmp = Join-Path $TestDrive 'settings.json'
  }

  It 'preserves unrelated keys and nested values' {
    $s = New-Settings '{"model":"opus","permissions":{"allow":["Bash(git *)"],"deny":[]},"env":{}}'
    Add-NotifyHook $s 'Stop' 'x "C:/u/.claude/hooks/claude-notify/notify-toast.ps1" -Message "Done"'
    Write-Settings $s $script:tmp
    $back = Read-Settings $script:tmp
    $back.model | Should -Be 'opus'
    @($back.permissions.allow) | Should -Be @('Bash(git *)')
    @($back.permissions.deny).Count | Should -Be 0
    (Get-Commands $back 'Stop') | Should -Be @('x "C:/u/.claude/hooks/claude-notify/notify-toast.ps1" -Message "Done"')
  }

  It 'writes two-space indented JSON without a BOM' {
    $s = New-Settings '{"a":{"b":[1,2]}}'
    Write-Settings $s $script:tmp
    $bytes = [IO.File]::ReadAllBytes($script:tmp)
    $bytes[0] | Should -Be ([byte][char]'{')
    $text = [IO.File]::ReadAllText($script:tmp)
    $text | Should -Match "`n  `"a`": \{`n    `"b`": \[`n      1,`n      2`n    \]`n  \}`n\}`n$"
  }

  It 'does not escape angle brackets, ampersands or apostrophes' {
    $s = New-Settings '{"cmd":"a < b > c & d''s"}'
    Write-Settings $s $script:tmp
    [IO.File]::ReadAllText($script:tmp) | Should -Match "a < b > c & d's"
  }

  It 'reads a missing or empty file as an empty object' {
    @((Read-Settings (Join-Path $TestDrive 'nope.json')).PSObject.Properties).Count | Should -Be 0
    Set-Content $script:tmp ''
    @((Read-Settings $script:tmp).PSObject.Properties).Count | Should -Be 0
  }
}

Describe 'Backup-Settings' {
  It 'returns null when the file does not exist' {
    Backup-Settings (Join-Path $TestDrive 'nope.json') | Should -BeNullOrEmpty
  }

  It 'copies the file to a timestamped .bak' {
    $p = Join-Path $TestDrive 'settings.json'
    Set-Content $p '{"x":1}'
    $b = Backup-Settings $p
    $b | Should -Match '\.bak-\d{8}-\d{6}$'
    Get-Content $b -Raw | Should -Be (Get-Content $p -Raw)
  }
}
