using System.Text.Json.Nodes;
using FluentDeck.Core.Deck;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using Microsoft.Extensions.Logging;

namespace FluentDeck.DevHost;

internal sealed class LoggingDeckExecutor(ILogger<LoggingDeckExecutor> log) : IDeckActionExecutor
{
    public Task ExecuteAsync(DeckAction action, CancellationToken ct)
    {
        if (action.Type == "keys") _ = KeyChord.ParseSequence(action.Keys ?? ""); // validate like the real host
        log.LogInformation("[deck] {Type} {Detail}", action.Type, action.Target ?? action.Keys ?? action.Text);
        return Task.CompletedTask;
    }

    /// <summary>A coloured tile per path, so different apps get different stand-in icons.</summary>
    public byte[]? TryGetIcon(string path)
    {
        var name = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        var (top, bottom) = Tints[(int)((uint)name.Aggregate(17, (h, c) => h * 31 + c) % (uint)Tints.Length)];
        return Png.Gradient(64, top, bottom, rounded: true);
    }

    private static readonly ((byte, byte, byte) Top, (byte, byte, byte) Bottom)[] Tints =
    [
        ((0x2B, 0x88, 0xD8), (0x0B, 0x3D, 0x91)), ((0x1E, 0xD7, 0x60), (0x12, 0x80, 0x3A)),
        ((0xF2, 0x6B, 0x3A), (0xA8, 0x32, 0x16)), ((0x8E, 0x6B, 0xF2), (0x4B, 0x2F, 0xB0)),
        ((0xF2, 0xC0, 0x3A), (0xB0, 0x78, 0x10)), ((0xE8, 0x4A, 0x8A), (0x9A, 0x1F, 0x55)),
    ];

    public IReadOnlyList<DeckApp> ListApps() =>
    [
        new("Discord", @"C:\Users\dev\AppData\Local\Discord\Discord.lnk"),
        new("File Explorer", @"C:\Windows\explorer.exe"),
        new("Figma", @"C:\Users\dev\AppData\Local\Figma\Figma.lnk"),
        new("Microsoft Edge", @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
        new("Notepad", @"C:\Windows\notepad.exe"),
        new("OBS Studio", @"C:\Program Files\obs-studio\bin\64bit\obs64.exe"),
        new("Spotify", @"C:\Users\dev\AppData\Roaming\Spotify\Spotify.exe"),
        new("Steam", @"C:\Program Files (x86)\Steam\steam.exe"),
        new("Visual Studio Code", @"C:\Users\dev\AppData\Local\Programs\Microsoft VS Code\Code.exe"),
        new("Windows Terminal", @"C:\Users\dev\AppData\Local\Microsoft\WindowsApps\wt.exe"),
    ];
}

internal static class Now
{
    public static long Ms => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}

/// <summary>A fake player cycling through a few tracks. Position advances in real time.</summary>
internal sealed class SimMediaPanel(AssetStore assets) : PanelProvider, IDisposable
{
    private sealed record Track(string Title, string Artist, string Album, double Duration, string? Art);

    private readonly object _gate = new();
    private Track[] _tracks = [];
    private int _index;
    private bool _playing = true;
    private double _position;
    private long _positionAt = Now.Ms;
    private bool _shuffle;
    private string _repeat = "none";
    private string _source = "Spotify.exe";
    private Timer? _timer;

    private static readonly MediaSource[] Sources = [new("Spotify.exe", "Spotify"), new("MSEdge", "Microsoft Edge")];

    public override PanelDescriptor Descriptor => BuiltInPanels.Media;

    public override Task StartAsync(CancellationToken ct)
    {
        _tracks =
        [
            new("Midnight Compile", "The Refactors", "Green Builds", 214, assets.Put(Png.Gradient(300, (0xF5, 0x6E, 0x48), (0x6A, 0x1B, 0x9A)))),
            new("Null Pointer Blues", "Segfault Sisters", "Core Dumped", 187, assets.Put(Png.Gradient(300, (0x00, 0xB4, 0xDB), (0x00, 0x33, 0x66)))),
            new("Merge Conflict", "Rebase", "Force Push", 245, assets.Put(Png.Gradient(300, (0x43, 0xE9, 0x7B), (0x38, 0x6E, 0x3C)))),
        ];
        Emit();
        _timer = new Timer(_ => Tick(), null, 1000, 1000);
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();
    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    private double CurrentPosition() => _playing ? _position + (Now.Ms - _positionAt) / 1000.0 : _position;

    private void Tick()
    {
        lock (_gate)
        {
            if (_playing && CurrentPosition() >= _tracks[_index].Duration) Skip(1);
        }
    }

    private void Skip(int delta)
    {
        _index = (_index + delta + _tracks.Length) % _tracks.Length;
        _position = 0; _positionAt = Now.Ms;
        Emit();
    }

    private void Emit()
    {
        var t = _tracks[_index];
        var source = Sources.First(s => s.AppId == _source);
        Publish(new MediaState(true, source, t.Title, t.Artist, t.Album, t.Art, _playing ? "playing" : "paused",
            Math.Round(CurrentPosition(), 2), t.Duration, Now.Ms, true, true, true, true, true, true, true, _shuffle, _repeat, Sources));
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        lock (_gate)
        {
            _position = CurrentPosition(); _positionAt = Now.Ms;
            switch (action)
            {
                case "playPause": _playing = !_playing; break;
                case "play": _playing = true; break;
                case "pause": _playing = false; break;
                case "next": Skip(1); return Task.FromResult<object?>(null);
                case "previous":
                    if (_position > 3) _position = 0; else { Skip(-1); return Task.FromResult<object?>(null); }
                    break;
                case "seek": _position = Math.Clamp(args.Double("seconds"), 0, _tracks[_index].Duration); break;
                case "shuffle": _shuffle = args.Bool("on", !_shuffle); break;
                case "repeat": _repeat = args.OptionalString("mode") ?? (_repeat == "none" ? "list" : _repeat == "list" ? "track" : "none"); break;
                case "selectSession":
                    var id = args.String("appId");
                    if (Sources.All(s => s.AppId != id)) throw new PanelActionException("No such media session");
                    _source = id; break;
                default: throw UnknownAction(action);
            }
            Emit();
        }
        return Task.FromResult<object?>(null);
    }
}

internal sealed class SimAudioPanel(AssetStore assets) : PanelProvider
{
    private readonly object _gate = new();
    private double _volume = 0.42, _mic = 0.8;
    private bool _muted, _micMuted;
    private string _default = "spk";
    private readonly Dictionary<string, (string Name, string? Icon, double Volume, bool Muted)> _apps = new();

    private static readonly (string Id, string Name)[] Devices = [("spk", "Speakers (Realtek Audio)"), ("hp", "Headphones (Surface Headphones 2)")];

    public override PanelDescriptor Descriptor => BuiltInPanels.Audio;

    public override Task StartAsync(CancellationToken ct)
    {
        _apps["spotify"] = ("Spotify", assets.Put(Png.Gradient(64, (0x1E, 0xD7, 0x60), (0x13, 0x85, 0x3B), true)), 1.0, false);
        _apps["edge"] = ("Microsoft Edge", assets.Put(Png.Gradient(64, (0x35, 0xC1, 0xF1), (0x0C, 0x59, 0xA4), true)), 0.7, false);
        _apps["teams"] = ("Microsoft Teams", assets.Put(Png.Gradient(64, (0x7B, 0x83, 0xEB), (0x4B, 0x53, 0xBC), true)), 0.9, false);
        _apps["system"] = ("System sounds", null, 0.5, false);
        Emit();
        return Task.CompletedTask;
    }

    private void Emit()
    {
        var dev = Devices.First(d => d.Id == _default);
        Publish(new AudioState(
            new AudioEndpointState(dev.Id, dev.Name, Math.Round(_volume, 3), _muted),
            new AudioEndpointState("mic", "Microphone Array (Realtek)", Math.Round(_mic, 3), _micMuted),
            Devices.Select(d => new AudioDevice(d.Id, d.Name, d.Id == _default)).ToList(),
            _apps.Select(kv => new AudioAppState(kv.Key, kv.Value.Name, kv.Value.Icon, Math.Round(kv.Value.Volume, 3), kv.Value.Muted, kv.Key != "system")).ToList()));
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        lock (_gate)
        {
            switch (action)
            {
                case "setVolume": _volume = args.Volume(); if (_volume > 0) _muted = false; break;
                case "toggleMute": _muted = !_muted; break;
                case "setMicVolume": _mic = args.Volume(); break;
                case "toggleMicMute": _micMuted = !_micMuted; break;
                case "setSessionVolume":
                {
                    var id = args.String("id");
                    if (!_apps.TryGetValue(id, out var a)) throw new PanelActionException("That app isn't playing audio anymore");
                    _apps[id] = a with { Volume = args.Volume() };
                    break;
                }
                case "toggleSessionMute":
                {
                    var id = args.String("id");
                    if (!_apps.TryGetValue(id, out var a)) throw new PanelActionException("That app isn't playing audio anymore");
                    _apps[id] = a with { Muted = !a.Muted };
                    break;
                }
                case "setDefaultDevice":
                    var dev = args.String("id");
                    if (Devices.All(d => d.Id != dev)) throw new PanelActionException("Unknown device");
                    _default = dev; break;
                default: throw UnknownAction(action);
            }
            Emit();
        }
        return Task.FromResult<object?>(null);
    }
}

internal sealed class SimSystemPanel(ILogger<SimSystemPanel> log, SystemDetails details) : PanelProvider, IDisposable
{
    private readonly Random _rng = new();
    private double _cpu = 12;
    private Timer? _timer;
    private int _battery = 76;

    public override PanelDescriptor Descriptor => BuiltInPanels.System;

    public override Task StartAsync(CancellationToken ct)
    {
        Emit();
        _timer = new Timer(_ => Emit(), null, 2000, 2000);
        return Task.CompletedTask;
    }

    public void Dispose() => _timer?.Dispose();
    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    private void Emit()
    {
        _cpu = Math.Clamp(_cpu + (_rng.NextDouble() - 0.5) * 12, 2, 96);
        Publish(new SystemState(Environment.MachineName, Math.Round(_cpu, 1), 61.3, 9.8, 16, new BatteryState(_battery, true),
            Environment.TickCount64 / 1000));
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        if (action == "details") return Task.FromResult<object?>(details.Sample()); // real disks and processes of this machine
        if (action is not ("lock" or "sleep" or "displayOff")) throw UnknownAction(action);
        log.LogInformation("[system] {Action} (simulated)", action);
        return Task.FromResult<object?>(null);
    }
}

internal sealed class SimThemePanel : PanelProvider
{
    public override PanelDescriptor Descriptor => BuiltInPanels.Theme;
    public override Task StartAsync(CancellationToken ct) { Publish(ThemeState.Default); return Task.CompletedTask; }
    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct) => throw UnknownAction(action);
}

/// <summary>Two named virtual desktops, the second for a full-screen remote session.</summary>
internal sealed class SimDesktopsPanel(ILogger<SimDesktopsPanel> log, HostSettings settings, HostPaths paths) : PanelProvider
{
    private readonly IReadOnlyList<DesktopInfo> _desktops = [new(1, "Desktop 1"), new(2, "Omnissa")];
    private int _current = 1;

    public override PanelDescriptor Descriptor => BuiltInPanels.Desktops;
    public override Task StartAsync(CancellationToken ct) { Emit(); return Task.CompletedTask; }

    private void Emit() => Publish(new DesktopsState(_current, _desktops, settings.RemoteReleaseKeys));

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        if (action == "configure")
        {
            DesktopSwitch.Configure(args, settings, paths);
            Emit();
            return Task.FromResult<object?>(null);
        }
        _current = DesktopSwitch.Target(action, args, _current, _desktops.Count);
        log.LogInformation("[desktops] {Action} -> desktop {Current} (simulated)", action, _current);
        Emit();
        return Task.FromResult<object?>(null);
    }
}

/// <summary>A few open apps, Visual Studio Code in front. "focus" brings one forward.</summary>
internal sealed class SimAppsPanel(AssetStore assets, ILogger<SimAppsPanel> log) : PanelProvider
{
    private List<RunningApp>? _running;
    private RunningApp? _front;

    public override PanelDescriptor Descriptor => BuiltInPanels.Apps;

    public override Task StartAsync(CancellationToken ct)
    {
        RunningApp App(string exe, string name, (byte, byte, byte) top, (byte, byte, byte) bottom) =>
            new(exe, name, $@"C:\Program Files\{name}\{exe}", assets.Put(Png.Gradient(64, top, bottom, rounded: true)));
        _running =
        [
            App("horizon-client.exe", "Omnissa Horizon Client", (0x5B, 0x8D, 0xEF), (0x1F, 0x3C, 0x88)),
            App("msedge.exe", "Microsoft Edge", (0x35, 0xC1, 0xF1), (0x0C, 0x59, 0xA4)),
            App("ms-teams.exe", "Microsoft Teams", (0x7B, 0x83, 0xEB), (0x4B, 0x53, 0xBC)),
            App("spotify.exe", "Spotify", (0x1E, 0xD7, 0x60), (0x13, 0x85, 0x3B)),
            App("code.exe", "Visual Studio Code", (0x3E, 0xA6, 0xF0), (0x0B, 0x5C, 0xA8)),
        ];
        _front = _running.First(a => a.Exe == "code.exe");
        Emit();
        return Task.CompletedTask;
    }

    private void Emit() => Publish(new AppsState(_front, _running!.OrderBy(a => a.Name).ToList()));

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        if (action != "focus") throw UnknownAction(action);
        var exe = args.String("exe");
        _front = _running!.FirstOrDefault(a => string.Equals(a.Exe, exe, StringComparison.OrdinalIgnoreCase))
                 ?? throw new PanelActionException($"{Path.GetFileNameWithoutExtension(exe)} isn't open on the PC.");
        log.LogInformation("[apps] focus {Exe} (simulated)", exe);
        Emit();
        return Task.FromResult<object?>(null);
    }
}

/// <summary>A clipboard that lives in memory.</summary>
internal sealed class SimClipboardPanel(ILogger<SimClipboardPanel> log) : PanelProvider
{
    private string _text = "Copied on the PC";

    public override PanelDescriptor Descriptor => BuiltInPanels.Clipboard;
    public override Task StartAsync(CancellationToken ct) { Publish(new { }); return Task.CompletedTask; }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        switch (action)
        {
            case "setText":
                _text = args.OptionalString("text") ?? "";
                log.LogInformation("[clipboard] set {Length} characters{Paste} (simulated)", _text.Length, args.Bool("paste") ? " and pasted" : "");
                return Task.FromResult<object?>(null);
            case "getText":
                return Task.FromResult<object?>(new { text = _text });
            default:
                throw UnknownAction(action);
        }
    }
}
