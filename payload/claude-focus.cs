using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

class ClaudeFocus {
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);

  [StructLayout(LayoutKind.Sequential)]
  struct POINT {
    public int X;
    public int Y;
  }

  [StructLayout(LayoutKind.Sequential)]
  struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [StructLayout(LayoutKind.Sequential)]
  struct WINDOWPLACEMENT {
    public int length;
    public int flags;
    public int showCmd;
    public POINT ptMinPosition;
    public POINT ptMaxPosition;
    public RECT rcNormalPosition;
  }

  const int SW_RESTORE = 9;
  const int SW_SHOWMAXIMIZED = 3;
  const int WPF_RESTORETOMAXIMIZED = 0x0002;
  const byte VK_MENU = 0x12;
  const uint KEYEVENTF_KEYUP = 0x0002;
  const uint SWP_NOMOVE = 0x0002;
  const uint SWP_NOSIZE = 0x0001;
  const uint SWP_SHOWWINDOW = 0x0040;
  static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

  static IntPtr ParseArg(string[] args) {
    long v;
    if (args.Length > 0) {
      string a = args[0].Trim().TrimEnd('/');
      int idx = a.IndexOf(':');
      if (idx >= 0) {
        a = a.Substring(idx + 1);
      }
      if (long.TryParse(a, out v) && v != 0) {
        return new IntPtr(v);
      }
    }
    string file = Path.Combine(Environment.GetEnvironmentVariable("TEMP"), "claude-code-window.txt");
    if (File.Exists(file) && long.TryParse(File.ReadAllText(file).Trim(), out v)) {
      return new IntPtr(v);
    }
    return IntPtr.Zero;
  }

  // only change show state when minimized; keeps maximized/fullscreen size intact
  static void Unminimize(IntPtr hwnd) {
    if (!IsIconic(hwnd)) {
      return;
    }
    WINDOWPLACEMENT wp = new WINDOWPLACEMENT();
    wp.length = Marshal.SizeOf(typeof(WINDOWPLACEMENT));
    bool toMax = GetWindowPlacement(hwnd, ref wp) && (wp.flags & WPF_RESTORETOMAXIMIZED) != 0;
    ShowWindow(hwnd, toMax ? SW_SHOWMAXIMIZED : SW_RESTORE);
  }

  static void TryFocus(IntPtr hwnd) {
    Unminimize(hwnd);

    // simulated Alt tap releases the foreground lock
    keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

    IntPtr fg = GetForegroundWindow();
    uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint targetThread = GetWindowThreadProcessId(hwnd, IntPtr.Zero);
    uint curThread = GetCurrentThreadId();

    bool attachedFg = fgThread != 0 && fgThread != curThread && AttachThreadInput(curThread, fgThread, true);
    bool attachedTarget = targetThread != 0 && targetThread != curThread && targetThread != fgThread && AttachThreadInput(curThread, targetThread, true);

    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);

    if (attachedTarget) {
      AttachThreadInput(curThread, targetThread, false);
    }
    if (attachedFg) {
      AttachThreadInput(curThread, fgThread, false);
    }
  }

  [STAThread]
  static void Main(string[] args) {
    try {
      IntPtr hwnd = ParseArg(args);
      if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) {
        return;
      }
      AllowSetForegroundWindow(-1);

      for (int i = 0; i < 10; i++) {
        TryFocus(hwnd);
        Thread.Sleep(60);
        if (GetForegroundWindow() == hwnd) {
          return;
        }
      }
      Unminimize(hwnd);
      SwitchToThisWindow(hwnd, false);
    } catch { }
  }
}
