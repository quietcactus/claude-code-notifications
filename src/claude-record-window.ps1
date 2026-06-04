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
