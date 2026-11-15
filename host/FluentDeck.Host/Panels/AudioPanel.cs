using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using Microsoft.Extensions.Logging;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace FluentDeck.Host.Panels;

/// <summary>
/// Volume mixer: default output + mic, per-app sessions with their real icons, and output device switching.
/// Polls Core Audio at ~3 Hz (plus endpoint change callbacks); identical states are de-duplicated upstream.
/// </summary>
internal sealed class AudioPanel : PanelProvider, IDisposable
{
    private readonly AssetStore _assets;
    private readonly ILogger<AudioPanel> _log;
    private readonly object _gate = new();
    private readonly Dictionary<uint, (string Name, string? Icon, DateTime Seen)> _processes = new();

    private MMDeviceEnumerator? _enumerator;
    private MMDevice? _output, _input;
    private System.Threading.Timer? _timer;
    private List<AudioDevice> _devices = [];
    private int _tick;

    public AudioPanel(AssetStore assets, ILogger<AudioPanel> log) { _assets = assets; _log = log; }

    public override PanelDescriptor Descriptor => BuiltInPanels.Audio;

    public override Task StartAsync(CancellationToken ct)
    {
        _enumerator = new MMDeviceEnumerator();
        Poll();
        _timer = new System.Threading.Timer(_ => Poll(), null, 300, 300);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    public void Dispose()
    {
        _timer?.Dispose(); _timer = null;
        lock (_gate)
        {
            ReleaseDevices();
            _enumerator?.Dispose(); _enumerator = null;
        }
    }

    private void ReleaseDevices()
    {
        if (_output is not null) { _output.AudioEndpointVolume.OnVolumeNotification -= OnEndpointChanged; _output.Dispose(); _output = null; }
        if (_input is not null) { _input.AudioEndpointVolume.OnVolumeNotification -= OnEndpointChanged; _input.Dispose(); _input = null; }
    }

    private void OnEndpointChanged(AudioVolumeNotificationData data) => ThreadPool.QueueUserWorkItem(_ => Poll());

    /// <summary>Re-acquire default devices when Windows' default changes.</summary>
    private void EnsureDefaults()
    {
        var e = _enumerator!;
        _output = Swap(_output, e.HasDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia) ? e.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia) : null);
        _input = Swap(_input, e.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Communications) ? e.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Communications) : null);
    }

    private MMDevice? Swap(MMDevice? current, MMDevice? fresh)
    {
        if (current is not null && fresh is not null && current.ID == fresh.ID) { fresh.Dispose(); return current; }
        if (current is not null) { current.AudioEndpointVolume.OnVolumeNotification -= OnEndpointChanged; current.Dispose(); }
        if (fresh is not null) fresh.AudioEndpointVolume.OnVolumeNotification += OnEndpointChanged;
        return fresh;
    }

    private void Poll()
    {
        if (!Monitor.TryEnter(_gate)) return; // a poll is already running
        try
        {
            if (_enumerator is null) return;
            EnsureDefaults();

            if (_tick++ % 7 == 0) // device list changes rarely; refresh every ~2 s
            {
                var list = new List<AudioDevice>();
                foreach (var d in _enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
                {
                    using (d) list.Add(new AudioDevice(d.ID, d.FriendlyName, d.ID == _output?.ID));
                }
                _devices = list;
            }
            else
            {
                _devices = _devices.Select(d => d with { IsDefault = d.Id == _output?.ID }).ToList();
            }

            Publish(new AudioState(
                Endpoint(_output),
                Endpoint(_input),
                _devices,
                _output is null ? [] : Sessions(_output)));
        }
        catch (COMException ex)
        {
            // Devices vanish (unplugged headset, driver reset). Drop them; the next poll re-acquires.
            _log.LogDebug(ex, "Audio poll failed; re-acquiring devices");
            ReleaseDevices();
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Audio poll failed");
        }
        finally
        {
            Monitor.Exit(_gate);
        }
    }

    private static AudioEndpointState? Endpoint(MMDevice? d) => d is null ? null :
        new AudioEndpointState(d.ID, d.FriendlyName, Math.Round(d.AudioEndpointVolume.MasterVolumeLevelScalar, 3), d.AudioEndpointVolume.Mute);

    private List<AudioAppState> Sessions(MMDevice device)
    {
        var manager = device.AudioSessionManager;
        manager.RefreshSessions();
        var sessions = manager.Sessions;
        var result = new List<AudioAppState>();
        for (var i = 0; i < sessions.Count; i++)
        {
            var s = sessions[i];
            try
            {
                if (s.State == AudioSessionState.AudioSessionStateExpired) continue;
                var pid = s.GetProcessID;
                string name; string? icon;
                if (s.IsSystemSoundsSession) { name = "System sounds"; icon = null; }
                else (name, icon) = Describe(pid);

                result.Add(new AudioAppState(
                    Id: s.GetSessionInstanceIdentifier,
                    Name: name,
                    Icon: icon,
                    Volume: Math.Round(s.SimpleAudioVolume.Volume, 3),
                    Muted: s.SimpleAudioVolume.Mute,
                    Active: s.State == AudioSessionState.AudioSessionStateActive));
            }
            finally
            {
                s.Dispose();
            }
        }
        // Like the Windows mixer: system sounds first, then apps alphabetically.
        return result.OrderBy(a => a.Name == "System sounds" ? 0 : 1).ThenBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    private (string Name, string? Icon) Describe(uint pid)
    {
        if (_processes.TryGetValue(pid, out var known)) return (known.Name, known.Icon);
        var path = Native.ProcessImagePath(pid);
        string name;
        try { name = path is null ? $"Process {pid}" : FileVersionInfo.GetVersionInfo(path).FileDescription is { Length: > 0 } d ? d : Path.GetFileNameWithoutExtension(path); }
        catch { name = path is null ? $"Process {pid}" : Path.GetFileNameWithoutExtension(path); }
        var icon = _assets.Put(IconExtractor.Png(path, 64), "image/png");
        _processes[pid] = (name, icon, DateTime.UtcNow);
        if (_processes.Count > 200)
            foreach (var old in _processes.OrderBy(kv => kv.Value.Seen).Take(100).ToList()) _processes.Remove(old.Key);
        return (name, icon);
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        lock (_gate)
        {
            if (_enumerator is null) throw new PanelActionException("Audio isn't available.");
            EnsureDefaults();
            switch (action)
            {
                case "setVolume":
                    var v = Out().AudioEndpointVolume;
                    v.MasterVolumeLevelScalar = args.Volume();
                    if (v.Mute && args.Volume() > 0) v.Mute = false;
                    break;
                case "toggleMute":
                    Out().AudioEndpointVolume.Mute = !Out().AudioEndpointVolume.Mute;
                    break;
                case "setMicVolume":
                    In().AudioEndpointVolume.MasterVolumeLevelScalar = args.Volume();
                    break;
                case "toggleMicMute":
                    In().AudioEndpointVolume.Mute = !In().AudioEndpointVolume.Mute;
                    break;
                case "setSessionVolume":
                    WithSession(args.String("id"), s => s.SimpleAudioVolume.Volume = args.Volume());
                    break;
                case "toggleSessionMute":
                    WithSession(args.String("id"), s => s.SimpleAudioVolume.Mute = !s.SimpleAudioVolume.Mute);
                    break;
                case "setDefaultDevice":
                    try { PolicyConfig.SetDefaultDevice(args.String("id")); }
                    catch (COMException ex) { throw new PanelActionException($"Windows refused to switch devices ({ex.Message})."); }
                    _tick = 0; // refresh the device list on the next poll
                    break;
                default:
                    throw UnknownAction(action);
            }
        }
        ThreadPool.QueueUserWorkItem(_ => Poll());
        return Task.FromResult<object?>(null);
    }

    private MMDevice Out() => _output ?? throw new PanelActionException("No output device.");
    private MMDevice In() => _input ?? throw new PanelActionException("No microphone found.");

    private void WithSession(string id, Action<AudioSessionControl> change)
    {
        var manager = Out().AudioSessionManager;
        manager.RefreshSessions();
        var sessions = manager.Sessions;
        for (var i = 0; i < sessions.Count; i++)
        {
            var s = sessions[i];
            try
            {
                if (s.GetSessionInstanceIdentifier == id) { change(s); return; }
            }
            finally { s.Dispose(); }
        }
        throw new PanelActionException("That app isn't playing audio anymore.");
    }
}
