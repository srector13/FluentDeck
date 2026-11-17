using System.Diagnostics;
using System.Text.Json.Nodes;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Host.Panels;

/// <summary>The app in front and the apps with windows open, checked every second, so the iPad can
/// switch boards to suit the app you're using; and "focus", which brings an app's window to the
/// front (Windows follows it to its desktop).</summary>
internal sealed class AppsPanel(AssetStore assets, ILogger<AppsPanel> log) : PanelProvider, IDisposable
{
    /// <summary>Windows that are part of the shell or of other apps, not apps of their own.</summary>
    private static readonly HashSet<string> Ignored = new(StringComparer.OrdinalIgnoreCase)
    {
        "applicationframehost.exe", "textinputhost.exe", "shellexperiencehost.exe", "startmenuexperiencehost.exe",
        "searchhost.exe", "lockapp.exe", "systemsettingsbroker.exe", "fluentdeck.host.exe",
    };

    private readonly Dictionary<string, RunningApp> _known = new(StringComparer.OrdinalIgnoreCase);
    private System.Threading.Timer? _timer;

    public override PanelDescriptor Descriptor => BuiltInPanels.Apps;

    public override Task StartAsync(CancellationToken ct)
    {
        Emit();
        _timer = new System.Threading.Timer(_ => Emit(), null, 1000, 1000);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }
    public void Dispose() { _timer?.Dispose(); _timer = null; }

    private void Emit()
    {
        try
        {
            var windows = AppWindows();
            var foreground = Native.GetForegroundWindow();
            var front = windows.FirstOrDefault(w => w.Hwnd == foreground).App ?? App(foreground);
            var running = windows.Select(w => w.App).DistinctBy(a => a.Exe)
                .OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
            Publish(new AppsState(front, running));
        }
        catch (Exception e) { log.LogDebug(e, "Couldn't list windows"); }
    }

    private List<(IntPtr Hwnd, RunningApp App)> AppWindows() =>
        WindowFocus.AppWindows().Select(w => (w.Hwnd, App(w.Hwnd))).Where(w => w.Item2 is not null)
            .Select(w => (w.Hwnd, w.Item2!)).ToList();

    private RunningApp? App(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        Native.GetWindowThreadProcessId(hwnd, out var pid);
        var path = Native.ProcessImagePath(pid);
        if (path is null) return null;
        var exe = Path.GetFileName(path).ToLowerInvariant();
        if (Ignored.Contains(exe)) return null;
        lock (_known)
        {
            if (_known.TryGetValue(path, out var known)) return known;
            string name;
            try { name = FileVersionInfo.GetVersionInfo(path).FileDescription is { Length: > 0 } d ? d : Path.GetFileNameWithoutExtension(path); }
            catch { name = Path.GetFileNameWithoutExtension(path); }
            var app = new RunningApp(exe, name, path, assets.Put(IconExtractor.Png(path, 64), "image/png"));
            if (_known.Count > 300) _known.Clear();
            return _known[path] = app;
        }
    }

    /// <summary>"focus" only brings an open app forward. Starting a program is left to deck keys
    /// (a "focus" action in deck.json), which a device can only create when the PC allows editing.</summary>
    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        if (action != "focus") throw UnknownAction(action);
        var exe = args.String("exe");
        var window = AppWindows().FirstOrDefault(w => string.Equals(w.App.Exe, exe, StringComparison.OrdinalIgnoreCase));
        if (window.Hwnd == IntPtr.Zero) throw new PanelActionException($"{Path.GetFileNameWithoutExtension(exe)} isn't open on the PC.");
        if (!WindowFocus.Bring(window.Hwnd)) throw new PanelActionException($"Windows wouldn't bring {window.App.Name} to the front.");
        Task.Delay(300, ct).ContinueWith(_ => Emit(), TaskScheduler.Default);
        return Task.FromResult<object?>(null);
    }
}
