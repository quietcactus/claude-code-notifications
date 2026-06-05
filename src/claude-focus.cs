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
