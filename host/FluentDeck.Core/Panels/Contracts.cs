namespace FluentDeck.Core.Panels;

// State shapes for the built-in topics. The Windows host and the DevHost simulators both publish
// these exact records, so the iPad can be developed against either. Serialized camelCase.

public static class BuiltInPanels
{
    public static readonly PanelDescriptor Media = new("media", "Media", "music.note", 1,
        ["playPause", "play", "pause", "next", "previous", "seek", "shuffle", "repeat", "selectSession"]);

    public static readonly PanelDescriptor Audio = new("audio", "Audio", "speaker.wave.2", 1,
        ["setVolume", "toggleMute", "setMicVolume", "toggleMicMute", "setSessionVolume", "toggleSessionMute", "setDefaultDevice"]);

    public static readonly PanelDescriptor System = new("system", "System", "cpu", 2,
        ["lock", "sleep", "displayOff", "details"]);

    public static readonly PanelDescriptor Theme = new("theme", "Theme", "paintpalette", 1, []);
}

public sealed record MediaSource(string AppId, string Name);

public sealed record MediaState(
    bool HasSession,
    MediaSource? Source,
    string? Title,
    string? Artist,
    string? Album,
    string? Artwork,
    // playing | paused | stopped | changing | closed
    string Status,
    double Position,
    double Duration,
    long PositionAt,
    bool CanPlay,
    bool CanPause,
    bool CanNext,
    bool CanPrevious,
    bool CanSeek,
    bool CanShuffle,
    bool CanRepeat,
    bool? Shuffle,
    // none | track | list
    string? Repeat,
    IReadOnlyList<MediaSource> Sessions)
{
    public static MediaState None(IReadOnlyList<MediaSource>? sessions = null) => new(
        false, null, null, null, null, null, "closed", 0, 0, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        false, false, false, false, false, false, false, null, null, sessions ?? []);
}

public sealed record AudioEndpointState(string Id, string Name, double Volume, bool Muted);
public sealed record AudioDevice(string Id, string Name, bool IsDefault);
public sealed record AudioAppState(string Id, string Name, string? Icon, double Volume, bool Muted, bool Active);

public sealed record AudioState(
    AudioEndpointState? Output,
    AudioEndpointState? Input,
    IReadOnlyList<AudioDevice> Devices,
    IReadOnlyList<AudioAppState> Sessions);

public sealed record BatteryState(int Percent, bool Charging);

public sealed record SystemState(
    string HostName,
    double Cpu,
    double Memory,
    double MemoryUsedGb,
    double MemoryTotalGb,
    BatteryState? Battery,
    long UptimeSeconds);

public sealed record ThemeState(
    bool IsDark,
    string Accent,
    string AccentLight1, string AccentLight2, string AccentLight3,
    string AccentDark1, string AccentDark2, string AccentDark3)
{
    /// <summary>Windows 11 default blue.</summary>
    public static readonly ThemeState Default = new(true, "#0078D4", "#0093F9", "#60CCFE", "#98ECFE", "#005FB8", "#004275", "#001A68");
}
