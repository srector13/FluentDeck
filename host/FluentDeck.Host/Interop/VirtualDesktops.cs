using System.Runtime.InteropServices;

namespace FluentDeck.Host.Interop;

/// <summary>Windows' documented virtual desktop interface: which desktop a window is on. Switching
/// desktops has no public API, but activating a window on another desktop takes Windows there,
/// with no keystrokes for a full-screen remote desktop to intercept.</summary>
internal static class VirtualDesktops
{
    [ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out int onCurrentDesktop);
        [PreserveSig] int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
        [PreserveSig] int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }

    [ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")]
    private class VirtualDesktopManager;

    private static IVirtualDesktopManager? _manager;

    private static IVirtualDesktopManager? Manager
    {
        get
        {
            try { return _manager ??= (IVirtualDesktopManager)new VirtualDesktopManager(); }
            catch { return null; }
        }
    }

    public static Guid? DesktopOf(IntPtr hwnd)
    {
        var manager = Manager;
        if (manager is null) return null;
        try { return manager.GetWindowDesktopId(hwnd, out var id) == 0 && id != Guid.Empty ? id : null; }
        catch { return null; }
    }

    /// <summary>The front-most app window on that desktop, or zero if it has none.</summary>
    public static IntPtr WindowOn(Guid desktop)
    {
        foreach (var (hwnd, _) in WindowFocus.AppWindows())
            if (DesktopOf(hwnd) == desktop) return hwnd;
        return IntPtr.Zero;
    }
}
