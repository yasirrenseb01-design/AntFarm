// AntDesk: the Win32 side of AntFarm's desktop mode (PART 11). The game (scripts/game/desktop_mode.gd) runs it with:
//   antdesk attach <hwnd>   put the game's window into the desktop's wallpaper layer, behind the icons, over the
//                           primary monitor; prints "ok <layout>" (exit 0) or an error (exit 2)
//   antdesk detach <hwnd>   take it out again (a normal top-level window, framed) and have the shell repaint the wallpaper
//                           (else the last frame stays on the desktop)
//   antdesk covered         prints 1 if a window covers the primary monitor (a maximized or full-screen app: the
//                           wallpaper cannot be seen, the game stops drawing), else 0
// Built by tools/build.ps1 with the C# compiler that comes with Windows (.NET Framework 4, C# 5):
//   csc /nologo /target:exe /out:build\AntDesk.exe tools\desktop\antdesk.cs
//
// The wallpaper layer (undocumented; as Lively Wallpaper and others do it): message 0x052C to Progman makes Explorer
// create a WorkerW behind the icons. Windows 11 24H2 and later: it is a child of Progman, below the icon view
// (SHELLDLL_DefView); before: a top-level WorkerW, the one after the WorkerW holding the icon view. The message
// must carry 0xD, 1 on 24H2+ (0, 0 is ignored there). The window must be made WS_CHILD before SetParent.
using System;
using System.Runtime.InteropServices;
using System.Text;

static class AntDesk
{
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from, IntPtr to, ref POINT pt, int n);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr lp);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SystemParametersInfo(uint action, uint param, StringBuilder pv, uint flags);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);

    delegate bool EnumProc(IntPtr hwnd, IntPtr lp);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
    const long WS_CHILD = 0x40000000, WS_POPUP = 0x80000000, WS_VISIBLE = 0x10000000;
    const long WS_CAPTION = 0x00C00000, WS_THICKFRAME = 0x00040000, WS_SYSMENU = 0x00080000;
    const long WS_OVERLAPPEDWINDOW = 0x00CF0000;     // caption, system menu, sizing frame, minimize and maximize boxes
    const long WS_EX_APPWINDOW = 0x00040000, WS_EX_TOOLWINDOW = 0x00000080;
    const uint SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040, SWP_FRAMECHANGED = 0x0020, SWP_NOZORDER = 0x0004;
    const uint SMTO_ABORTIFHUNG = 0x0002;
    const long WS_EX_LAYERED = 0x00080000, WS_EX_NOREDIRECTIONBITMAP = 0x00200000;
    const uint SWP_NOMOVE = 0x0002, SWP_NOSIZE = 0x0001, LWA_ALPHA = 0x2;
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint key, byte alpha, uint flags);
    const uint SPI_GETDESKWALLPAPER = 0x0073, SPI_SETDESKWALLPAPER = 0x0014, SPIF_SENDCHANGE = 0x02;

    static int Main(string[] args)
    {
        SetProcessDPIAware();                      // (the monitor's real pixels, as the game's window uses them)
        try
        {
            if (args.Length >= 2 && args[0] == "attach") return Attach(new IntPtr(long.Parse(args[1])));
            if (args.Length >= 2 && args[0] == "detach") return Detach(new IntPtr(long.Parse(args[1])));
            if (args.Length >= 1 && args[0] == "covered") { Console.WriteLine(Covered() ? "1" : "0"); return 0; }
            if (args.Length >= 1 && args[0] == "probe") { Console.WriteLine(Probe()); return 0; }
            if (args.Length >= 2 && args[0] == "snap") return Snap(args[1]);
            if (args.Length >= 2 && args[0] == "snapdwm") return SnapDwm(args[1]);
            if (args.Length >= 1 && args[0] == "zorder")
            {
                // Progman's children top to bottom (dev)
                IntPtr pm = FindWindow("Progman", null);
                IntPtr c = IntPtr.Zero;
                while ((c = FindWindowEx(pm, c, null, null)) != IntPtr.Zero)
                {
                    uint pid;
                    GetWindowThreadProcessId(c, out pid);
                    Console.WriteLine(string.Format("{0} {1} pid {2} visible {3}", c.ToInt64(), ClassOf(c), pid, IsWindowVisible(c)));
                }
                return 0;
            }
            if (args.Length >= 2 && args[0] == "info")
            {
                IntPtr h = new IntPtr(long.Parse(args[1]));
                RECT r;
                GetWindowRect(h, out r);
                IntPtr par = GetParent(h);
                int cloaked;
                DwmGetWindowAttribute(h, 14, out cloaked, 4);
                Console.WriteLine(string.Format("window {0} visible {1} iconic {2} cloaked {3} style {4:X} ex {5:X} parent {6} ({7}) rect {8},{9} {10}x{11}", h.ToInt64(),
                    IsWindowVisible(h), IsIconic(h), cloaked, GetWindowLongPtr(h, GWL_STYLE).ToInt64(), GetWindowLongPtr(h, GWL_EXSTYLE).ToInt64(),
                    par.ToInt64(), ClassOf(par), r.L, r.T, r.R - r.L, r.B - r.T));
                return 0;
            }
        }
        catch (Exception e)
        {
            Console.WriteLine("error " + e.Message);
            return 2;
        }
        Console.WriteLine("usage: antdesk attach <hwnd> | detach <hwnd> | covered | probe");
        return 1;
    }

    static string ClassOf(IntPtr h)
    {
        StringBuilder s = new StringBuilder(256);
        GetClassName(h, s, 256);
        return s.ToString();
    }

    static RECT Primary()
    {
        POINT origin = new POINT();
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(MonitorFromPoint(origin, 1), ref mi);     // (MONITOR_DEFAULTTOPRIMARY)
        return mi.rcMonitor;
    }

    // The wallpaper layer: [the WorkerW, "24h2" or "classic"], or [IntPtr.Zero, why not].
    static object[] FindLayer()
    {
        IntPtr progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero) return new object[] { IntPtr.Zero, "no Progman" };
        IntPtr res;
        SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(1), SMTO_ABORTIFHUNG, 1000, out res);
        uint shell;
        GetWindowThreadProcessId(progman, out shell);
        // Windows 11 24H2+: a WorkerW child of Progman (the icon view is Progman's own child there)
        IntPtr w = IntPtr.Zero;
        while ((w = FindWindowEx(progman, w, "WorkerW", null)) != IntPtr.Zero)
        {
            if (FindWindowEx(w, IntPtr.Zero, "SHELLDLL_DefView", null) == IntPtr.Zero) return new object[] { w, "24h2" };
        }
        // before: the top-level WorkerW after the one that holds the icon view (Explorer's own, not another program's)
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate (IntPtr top, IntPtr lp)
        {
            if (FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null) != IntPtr.Zero)
            {
                IntPtr next = FindWindowEx(IntPtr.Zero, top, "WorkerW", null);
                uint pid;
                GetWindowThreadProcessId(next, out pid);
                if (next != IntPtr.Zero && pid == shell) { found = next; return false; }
            }
            return true;
        }, IntPtr.Zero);
        if (found != IntPtr.Zero) return new object[] { found, "classic" };
        return new object[] { IntPtr.Zero, "no wallpaper layer" };
    }

    static string Probe()
    {
        object[] l = FindLayer();
        RECT p = Primary();
        return string.Format("layer {0} {1}  primary {2},{3} {4}x{5}", ((IntPtr)l[0]).ToInt64(), l[1], p.L, p.T, p.R - p.L, p.B - p.T);
    }

    static int Attach(IntPtr hwnd)
    {
        if (!IsWindow(hwnd)) { Console.WriteLine("error no such window"); return 2; }
        object[] l = FindLayer();
        IntPtr layer = (IntPtr)l[0];
        if (layer == IntPtr.Zero) { Console.WriteLine("error " + l[1]); return 2; }
        // Windows 11 24H2+ ("raised desktop": Progman draws with no redirection bitmap): a child of the wallpaper WorkerW
        // is not shown there. As Lively does: a child of Progman itself, layered (opaque), placed right below the icon
        // view, with the WorkerW (Explorer's own wallpaper) kept last, under it.
        IntPtr progman = FindWindow("Progman", null);
        bool raised = (GetWindowLongPtr(progman, GWL_EXSTYLE).ToInt64() & WS_EX_NOREDIRECTIONBITMAP) != 0;
        string trial = Environment.GetEnvironmentVariable("ANTDESK_TRIAL") ?? "";      // (dev: other ways tried)
        if (trial.Contains("workerw")) raised = false;
        IntPtr parent = raised ? progman : layer;
        // a child window first (else it is half attached: no parent, wrong position), no frame, not in the taskbar
        long st = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
        st = (st & ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU)) | WS_CHILD | WS_VISIBLE;
        SetWindowLongPtr(hwnd, GWL_STYLE, new IntPtr(st));
        long ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        ex = (ex & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
        if (raised && !trial.Contains("nolayer")) ex |= WS_EX_LAYERED;
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex));
        if (raised && !trial.Contains("nolayer")) SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
        if (SetParent(hwnd, parent) == IntPtr.Zero && GetParent(hwnd) != parent)
        {
            Console.WriteLine("error SetParent " + Marshal.GetLastWin32Error());
            return 2;
        }
        // over the primary monitor, in the parent's own coordinates
        RECT p = Primary();
        POINT at = new POINT();
        at.X = p.L;
        at.Y = p.T;
        MapWindowPoints(IntPtr.Zero, parent, ref at, 1);
        SetWindowPos(hwnd, IntPtr.Zero, at.X, at.Y, p.R - p.L, p.B - p.T, SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
        if (raised)
        {
            IntPtr icons = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (icons != IntPtr.Zero)
                SetWindowPos(hwnd, icons, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);     // (just below the icons)
            SetWindowPos(layer, new IntPtr(1), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);  // (HWND_BOTTOM: the old wallpaper under it)
        }
        Console.WriteLine("ok " + l[1] + (raised ? " raised" : ""));
        return 0;
    }

    static int Detach(IntPtr hwnd)
    {
        if (IsWindow(hwnd))
        {
            SetParent(hwnd, IntPtr.Zero);
            // a normal window again, with its title bar and frame (attach took them off; left a frameless popup, the game
            // came back with no border and no close button - v0.11.0, the player); the game then sets its own style
            long st = GetWindowLongPtr(hwnd, GWL_STYLE).ToInt64();
            st = (st & ~(WS_CHILD | WS_POPUP)) | WS_OVERLAPPEDWINDOW | WS_VISIBLE;
            SetWindowLongPtr(hwnd, GWL_STYLE, new IntPtr(st));
            long ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
            SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr((ex & ~(WS_EX_TOOLWINDOW | WS_EX_LAYERED)) | WS_EX_APPWINDOW));
            SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | SWP_NOZORDER | SWP_FRAMECHANGED);   // (SWP_NOSIZE | SWP_NOMOVE)
        }
        // the wallpaper layer keeps the last frame drawn on it: set the same wallpaper again to have it repainted
        StringBuilder path = new StringBuilder(1024);
        if (SystemParametersInfo(SPI_GETDESKWALLPAPER, (uint)path.Capacity, path, 0) && path.Length > 0)
            SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_SENDCHANGE);
        Console.WriteLine("ok");
        return 0;
    }

    // Dev: the desktop as it shows with no windows over it (the wallpaper layer and the icons) to a PNG - to check
    // desktop mode without covering the keeper's screen.
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    static int Snap(string path)
    {
        IntPtr progman = FindWindow("Progman", null);
        RECT r;
        GetWindowRect(progman, out r);
        using (System.Drawing.Bitmap bmp = new System.Drawing.Bitmap(Math.Max(1, r.R - r.L), Math.Max(1, r.B - r.T)))
        {
            using (System.Drawing.Graphics g = System.Drawing.Graphics.FromImage(bmp))
            {
                IntPtr dc = g.GetHdc();
                PrintWindow(progman, dc, 2);          // (PW_RENDERFULLCONTENT: what DWM composes, children included)
                g.ReleaseHdc(dc);
            }
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        Console.WriteLine("ok");
        return 0;
    }

    // Dev: the desktop as DWM composes it (PrintWindow misses what the GPU draws into a child window): a small window
    // shows a live thumbnail of Progman for half a second in the screen's corner, and is captured.
    [DllImport("dwmapi.dll")] static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumb);
    [DllImport("dwmapi.dll")] static extern int DwmUpdateThumbnailProperties(IntPtr thumb, ref DWM_THUMBNAIL_PROPERTIES p);
    [DllImport("dwmapi.dll")] static extern int DwmUnregisterThumbnail(IntPtr thumb);
    [StructLayout(LayoutKind.Sequential)]
    struct DWM_THUMBNAIL_PROPERTIES { public int dwFlags; public RECT rcDestination; public RECT rcSource; public byte opacity; public bool fVisible; public bool fSourceClientAreaOnly; }
    static int SnapDwm(string path)
    {
        IntPtr progman = FindWindow("Progman", null);
        int w = 960, h = 540;
        System.Windows.Forms.Form f = new System.Windows.Forms.Form();
        f.FormBorderStyle = System.Windows.Forms.FormBorderStyle.None;
        f.StartPosition = System.Windows.Forms.FormStartPosition.Manual;
        f.TopMost = true;
        f.ShowInTaskbar = false;
        f.Location = new System.Drawing.Point(0, 0);
        f.Size = new System.Drawing.Size(w, h);
        f.Show();
        IntPtr thumb;
        DwmRegisterThumbnail(f.Handle, progman, out thumb);
        DWM_THUMBNAIL_PROPERTIES p = new DWM_THUMBNAIL_PROPERTIES();
        p.dwFlags = 0x1 | 0x4 | 0x8;              // (RECTDESTINATION | OPACITY | VISIBLE)
        p.rcDestination.R = w;
        p.rcDestination.B = h;
        p.opacity = 255;
        p.fVisible = true;
        DwmUpdateThumbnailProperties(thumb, ref p);
        for (int i = 0; i < 10; i++) { System.Windows.Forms.Application.DoEvents(); System.Threading.Thread.Sleep(50); }
        using (System.Drawing.Bitmap bmp = new System.Drawing.Bitmap(w, h))
        {
            using (System.Drawing.Graphics g = System.Drawing.Graphics.FromImage(bmp))
                g.CopyFromScreen(f.Location.X, f.Location.Y, 0, 0, bmp.Size);
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        DwmUnregisterThumbnail(thumb);
        f.Close();
        Console.WriteLine("ok");
        return 0;
    }

    // A visible, not minimized, not cloaked top-level window (not the desktop's own) covering 95% of the primary monitor.
    static bool Covered()
    {
        RECT p = Primary();
        long area = (long)(p.R - p.L) * (p.B - p.T);
        bool covered = false;
        EnumWindows(delegate (IntPtr h, IntPtr lp)
        {
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            string c = ClassOf(h);
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd" || c == "Shell_SecondaryTrayWnd") return true;
            int cloaked;
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;   // (DWMWA_CLOAKED: on another virtual desktop, a hidden app)
            long ex = GetWindowLongPtr(h, GWL_EXSTYLE).ToInt64();
            if ((ex & WS_EX_TOOLWINDOW) != 0) return true;
            RECT r;
            if (!GetWindowRect(h, out r)) return true;
            long ix = Math.Max(0, Math.Min(r.R, p.R) - Math.Max(r.L, p.L));
            long iy = Math.Max(0, Math.Min(r.B, p.B) - Math.Max(r.T, p.T));
            if (ix * iy >= area * 95 / 100) { covered = true; return false; }
            return true;
        }, IntPtr.Zero);
        return covered;
    }
}
