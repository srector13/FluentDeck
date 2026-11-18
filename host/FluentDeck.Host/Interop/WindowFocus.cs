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

    /// <summary>The program behind the window in front, as a lower-case file name.</summary>
    public static string? ForegroundExe()
    {
        var hwnd = Native.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return null;
        Native.GetWindowThreadProcessId(hwnd, out var pid);
        var path = Native.ProcessImagePath(pid);
        return path is null ? null : Path.GetFileName(path).ToLowerInvariant();
    }

    /// <summary>If a full-screen remote desktop has the keyboard, press its release keys so what
    /// FluentDeck does next happens on this PC, not the remote one.</summary>
    public static void ReleaseRemoteDesktop(string releaseKeys)
    {
        if (string.IsNullOrWhiteSpace(releaseKeys)) return;
        if (ForegroundExe() is not { } exe || !Core.Panels.DesktopSwitch.RemoteClients.Contains(exe)) return;
        try
        {
            KeyInput.SendChords(Core.Deck.KeyChord.ParseSequence(releaseKeys));
            Thread.Sleep(150);
        }
        catch (FormatException) { /* checked when saved */ }
    }

    /// <summary>Restore the window if minimized and put it in front. Joining the input of the
    /// window in front first is what lets a background app do this without a keystroke; tapping
    /// Alt is the fallback.</summary>
    public static bool Bring(IntPtr hwnd)
    {
        if (Native.IsIconic(hwnd)) Native.ShowWindow(hwnd, Native.SW_RESTORE);
        var front = Native.GetForegroundWindow();
        var frontThread = front == IntPtr.Zero ? 0 : Native.GetWindowThreadProcessId(front, out _);
        var me = Native.GetCurrentThreadId();
        var attached = frontThread != 0 && frontThread != me && Native.AttachThreadInput(me, frontThread, true);
        bool ok;
        try
        {
            Native.BringWindowToTop(hwnd);
            ok = Native.SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) Native.AttachThreadInput(me, frontThread, false);
        }
        if (!ok || Native.GetForegroundWindow() != hwnd)
        {
            KeyInput.Tap(0x12); // Alt
            ok = Native.SetForegroundWindow(hwnd);
        }
        return ok;
    }
}
