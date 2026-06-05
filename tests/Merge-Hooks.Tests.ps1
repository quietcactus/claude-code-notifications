Describe 'Merge-ClaudeHooks' {
  BeforeAll {
    . "$PSScriptRoot\..\install.ps1" -DotSourceOnly
  }

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
