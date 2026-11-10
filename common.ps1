$Markers = @('notify-toast.ps1', 'claude-record-window.ps1')
$ProtocolKey = 'Software\Classes\claudefocus'

function Get-ClaudeDir([string]$override) {
  if ($override) {
    return $override
  }
  if ($env:CLAUDE_CONFIG_DIR) {
    return $env:CLAUDE_CONFIG_DIR
  }
  return Join-Path $env:USERPROFILE '.claude'
}

function Read-Settings([string]$path) {
  if (-not (Test-Path $path)) {
    return [pscustomobject]@{}
  }
  $raw = Get-Content $path -Raw -Encoding UTF8
  if (-not $raw -or -not $raw.Trim()) {
    return [pscustomobject]@{}
  }
  return $raw | ConvertFrom-Json
}

function Format-Json([string]$json) {
  $sb = New-Object Text.StringBuilder
  $level = 0
  $inStr = $false
  $esc = $false
  $pad = { param($n) "`n" + ('  ' * $n) }
  foreach ($ch in $json.ToCharArray()) {
    if ($inStr) {
      [void]$sb.Append($ch)
      if ($esc) {
        $esc = $false
      } elseif ($ch -eq [char]'\') {
        $esc = $true
      } elseif ($ch -eq [char]'"') {
        $inStr = $false
      }
      continue
    }
    if ($ch -eq [char]'"') {
      $inStr = $true
      [void]$sb.Append($ch)
    } elseif ($ch -eq [char]'{' -or $ch -eq [char]'[') {
      $level++
      [void]$sb.Append($ch).Append((& $pad $level))
    } elseif ($ch -eq [char]'}' -or $ch -eq [char]']') {
      $level--
      [void]$sb.Append((& $pad $level)).Append($ch)
    } elseif ($ch -eq [char]',') {
      [void]$sb.Append($ch).Append((& $pad $level))
    } elseif ($ch -eq [char]':') {
      [void]$sb.Append(': ')
    } elseif (-not [char]::IsWhiteSpace($ch)) {
      [void]$sb.Append($ch)
    }
  }
  $out = $sb.ToString()
  $out = $out -replace '\{\n\s*\}', '{}' -replace '\[\n\s*\]', '[]'
  $out = $out -replace '(?<!\\)\\u0027', "'" -replace '(?<!\\)\\u003c', '<' -replace '(?<!\\)\\u003e', '>' -replace '(?<!\\)\\u0026', '&'
  return $out
}

function Write-Settings($settings, [string]$path) {
  $json = Format-Json ($settings | ConvertTo-Json -Depth 100)
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  [IO.File]::WriteAllText($path, $json + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Backup-Settings([string]$path) {
  if (Test-Path $path) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$path.bak-$stamp"
    Copy-Item $path $backup
    return $backup
  }
  return $null
}

function Test-NotifyCommand($cmd) {
  foreach ($m in $Markers) {
    if ([string]$cmd -like "*$m*") {
      return $true
    }
  }
  return $false
}

function Remove-NotifyHooks($settings) {
  $removed = 0
  if (-not $settings.PSObject.Properties['hooks']) {
    return $removed
  }
  $hooks = $settings.hooks
  foreach ($evt in @($hooks.PSObject.Properties.Name)) {
    $kept = @()
    foreach ($group in @($hooks.$evt)) {
      $inner = @($group.hooks)
      $innerKept = @($inner | Where-Object { -not (Test-NotifyCommand $_.command) })
      $removed += $inner.Count - $innerKept.Count
      if ($innerKept.Count -gt 0) {
        $group.hooks = $innerKept
        $kept += $group
      }
    }
    if ($kept.Count -gt 0) {
      $hooks.$evt = $kept
    } else {
      $hooks.PSObject.Properties.Remove($evt)
    }
  }
  if (@($hooks.PSObject.Properties).Count -eq 0) {
    $settings.PSObject.Properties.Remove('hooks')
  }
  return $removed
}

function Add-NotifyHook($settings, [string]$evt, [string]$command) {
  if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{})
  }
  $group = [pscustomobject]@{
    matcher = ''
    hooks = @([pscustomobject]@{ type = 'command'; command = $command })
  }
  $hooks = $settings.hooks
  if ($hooks.PSObject.Properties[$evt]) {
    $hooks.$evt = @($hooks.$evt) + $group
  } else {
    $hooks | Add-Member -NotePropertyName $evt -NotePropertyValue @($group)
  }
}
