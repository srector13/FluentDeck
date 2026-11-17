namespace FluentDeck.Host.Interop;

/// <summary>Finds an app's windows by its program and brings one to the front. Windows switches to
/// the window's virtual desktop when it does.</summary>
internal static class WindowFocus
{
    /// <summary>Top-level windows a person would call an app's window, front to back, with the
    /// process behind each.</summary>
    public static List<(IntPtr Hwnd, uint Pid)> AppWindows()
    {
        var list = new List<(IntPtr, uint)>();
        Native.EnumWindows((hwnd, _) =>
        {
            if (!Native.IsWindowVisible(hwnd) || Native.GetWindowTextLength(hwnd) == 0) return true;
            if (Native.GetWindow(hwnd, Native.GW_OWNER) != IntPtr.Zero) return true;
            if ((Native.GetWindowLongPtr(hwnd, Native.GWL_EXSTYLE).ToInt64() & Native.WS_EX_TOOLWINDOW) != 0) return true;
            Native.GetWindowThreadProcessId(hwnd, out var pid);
            list.Add((hwnd, pid));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// <summary>The front-most window of the program with this file name ("code.exe"), or zero.</summary>
    public static IntPtr Find(string exe)
    {
        foreach (var (hwnd, pid) in AppWindows())
        {
            var path = Native.ProcessImagePath(pid);
            if (path is not null && string.Equals(Path.GetFileName(path), exe, StringComparison.OrdinalIgnoreCase)) return hwnd;
        }
        return IntPtr.Zero;
    }

    /// <summary>Restore the window if minimized and put it in front.</summary>
    public static bool Bring(IntPtr hwnd)
    {
        if (Native.IsIconic(hwnd)) Native.ShowWindow(hwnd, Native.SW_RESTORE);
        KeyInput.Tap(0x12); // Alt: lets a background app hand over the foreground
        return Native.SetForegroundWindow(hwnd);
    }
}
