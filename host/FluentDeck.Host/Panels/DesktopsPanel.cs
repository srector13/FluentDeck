using System.Diagnostics;
using System.Text.Json.Nodes;
using FluentDeck.Core.Deck;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;

namespace FluentDeck.Host.Panels;

/// <summary>Windows' virtual desktops: their names and which one is showing, read from the registry
/// a few times a second, and switching between them.
///
/// Windows has no public API to switch desktops. In order, this:
/// 1. presses the release keys of a full-screen remote desktop (Omnissa Horizon, Remote Desktop)
///    if one is in front, so it lets go of the keyboard;
/// 2. activates a window that's on the target desktop, which takes Windows there with no
///    keystrokes at all;
/// 3. failing that (an empty desktop), puts the taskbar in front and presses Ctrl+Win+Left/Right
///    as many times as it takes.</summary>
internal sealed class DesktopsPanel(ILogger<DesktopsPanel> log, HostSettings settings, HostPaths paths) : PanelProvider, IDisposable
{
    private const string Root = @"Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops";
    private System.Threading.Timer? _timer;
    private readonly SemaphoreSlim _switching = new(1, 1);

    public override PanelDescriptor Descriptor => BuiltInPanels.Desktops;

    public override Task StartAsync(CancellationToken ct)
    {
        Emit();
        _timer = new System.Threading.Timer(_ => Emit(), null, 700, 700);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }
    public void Dispose() { _timer?.Dispose(); _timer = null; }

    private void Emit()
    {
        try { Publish(Read()); }
        catch (Exception e) { log.LogDebug(e, "Couldn't read the virtual desktops"); }
    }

    /// <summary>Windows 11 keeps the desktop list and the current desktop under VirtualDesktops;
    /// Windows 10 keeps the current one per logon session.</summary>
    private DesktopsState Read() => ReadDesktops() with { ReleaseKeys = settings.RemoteReleaseKeys };

    private static List<Guid> Ids()
    {
        using var key = Registry.CurrentUser.OpenSubKey(Root);
        return Guids(key?.GetValue("VirtualDesktopIDs") as byte[]);
    }

    private static DesktopsState ReadDesktops()
    {
        using var key = Registry.CurrentUser.OpenSubKey(Root);
        var ids = Guids(key?.GetValue("VirtualDesktopIDs") as byte[]);
        var current = key?.GetValue("CurrentVirtualDesktop") as byte[];
        if (current is null)
        {
            using var session = Registry.CurrentUser.OpenSubKey(
                $@"Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\{Process.GetCurrentProcess().SessionId}\VirtualDesktops");
            current = session?.GetValue("CurrentVirtualDesktop") as byte[];
        }

        // With a single desktop Windows may not have written the list yet.
        if (ids.Count == 0) return new DesktopsState(1, [new DesktopInfo(1, "Desktop 1")]);

        var desktops = ids.Select((id, i) => new DesktopInfo(i + 1, Name(id) ?? $"Desktop {i + 1}")).ToList();
        var index = current is { Length: 16 } ? ids.IndexOf(new Guid(current)) + 1 : 0;
        return new DesktopsState(index, desktops);
    }

    private static List<Guid> Guids(byte[]? bytes)
    {
        var list = new List<Guid>();
        if (bytes is null) return list;
        for (var i = 0; i + 16 <= bytes.Length; i += 16) list.Add(new Guid(bytes.AsSpan(i, 16)));
        return list;
    }

    private static string? Name(Guid id)
    {
        using var key = Registry.CurrentUser.OpenSubKey($@"{Root}\Desktops\{id:B}");
        return key?.GetValue("Name") is string name && !string.IsNullOrWhiteSpace(name) ? name : null;
    }

    public override async Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        if (action == "configure")
        {
            DesktopSwitch.Configure(args, settings, paths);
            Emit();
            return null;
        }
        await _switching.WaitAsync(ct);
        try
        {
            var state = Read();
            var target = DesktopSwitch.Target(action, args, state.Current, state.Desktops.Count);
            if (state.Current == 0) throw new PanelActionException("Windows didn't say which desktop is showing, so FluentDeck can't tell which way to go.");
            if (target == state.Current) return null;

            WindowFocus.ReleaseRemoteDesktop(settings.RemoteReleaseKeys);

            // A window on the target desktop: bring it forward and Windows follows.
            var ids = Ids();
            if (ids.Count >= target)
            {
                var window = VirtualDesktops.WindowOn(ids[target - 1]);
                if (window != IntPtr.Zero && WindowFocus.Bring(window))
                {
                    await Task.Delay(300, ct);
                    if (Read().Current == target) { Emit(); return null; }
                }
            }

            // An empty desktop, or Windows said no: the keyboard shortcut, from the taskbar.
            var current = Read().Current;
            var steps = target - (current == 0 ? state.Current : current);
            FocusTaskbar();
            var chord = KeyChord.Parse(steps > 0 ? "Ctrl+Win+Right" : "Ctrl+Win+Left");
            for (var i = 0; i < Math.Abs(steps); i++)
            {
                KeyInput.SendChords([chord]);
                await Task.Delay(120, ct); // let the slide animation start before the next press
            }
            await Task.Delay(250, ct);
            Emit();
            if (Read().Current != target)
                log.LogInformation("Desktop switch to {Target} didn't land (on {Current})", target, Read().Current);
            return null;
        }
        finally { _switching.Release(); }
    }

    /// <summary>Bring the taskbar (on every desktop) to the front so the shortcut goes to Windows.</summary>
    private static void FocusTaskbar()
    {
        var taskbar = Native.FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero || Native.GetForegroundWindow() == taskbar) return;
        WindowFocus.Bring(taskbar);
        Thread.Sleep(60);
    }
}
