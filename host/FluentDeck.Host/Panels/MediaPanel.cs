using System.Diagnostics;
using System.Text.Json.Nodes;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using Microsoft.Extensions.Logging;
using Windows.Foundation;
using Windows.Media;
using Windows.Media.Control;
using Session = Windows.Media.Control.GlobalSystemMediaTransportControlsSession;
using SessionManager = Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager;

namespace FluentDeck.Host.Panels;

/// <summary>
/// Now Playing via Windows' System Media Transport Controls — the same source as the media flyout
/// in Quick Settings, so it works with Spotify, Apple Music, browsers, VLC, etc. with no per-app code.
/// </summary>
internal sealed class MediaPanel : PanelProvider, IDisposable
{
    private readonly AssetStore _assets;
    private readonly ILogger<MediaPanel> _log;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private readonly Dictionary<string, string> _appNames = new(StringComparer.OrdinalIgnoreCase);

    private SessionManager? _manager;
    private Session? _session;
    private string? _pinnedAppId;
    private int _refreshQueued;
    private string? _artFor, _artPath;
    private System.Threading.Timer? _safetyPoll;

    // Stored so they can be unsubscribed (WinRT events are removed by delegate identity).
    private readonly TypedEventHandler<SessionManager, CurrentSessionChangedEventArgs> _onCurrentChanged;
    private readonly TypedEventHandler<SessionManager, SessionsChangedEventArgs> _onSessionsChanged;
    private readonly TypedEventHandler<Session, MediaPropertiesChangedEventArgs> _onProps;
    private readonly TypedEventHandler<Session, PlaybackInfoChangedEventArgs> _onPlayback;
    private readonly TypedEventHandler<Session, TimelinePropertiesChangedEventArgs> _onTimeline;

    public MediaPanel(AssetStore assets, ILogger<MediaPanel> log)
    {
        _assets = assets; _log = log;
        _onCurrentChanged = (_, _) => QueueRefresh();
        _onSessionsChanged = (_, _) => QueueRefresh();
        _onProps = (_, _) => QueueRefresh();
        _onPlayback = (_, _) => QueueRefresh();
        _onTimeline = (_, _) => QueueRefresh();
    }

    public override PanelDescriptor Descriptor => BuiltInPanels.Media;

    public override async Task StartAsync(CancellationToken ct)
    {
        _manager = await SessionManager.RequestAsync();
        _manager.CurrentSessionChanged += _onCurrentChanged;
        _manager.SessionsChanged += _onSessionsChanged;
        await RefreshAsync();
        // Some players under-report events; a slow poll keeps everything honest.
        _safetyPoll = new System.Threading.Timer(_ => QueueRefresh(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    public void Dispose()
    {
        _safetyPoll?.Dispose();
        Attach(null);
        if (_manager is not null)
        {
            _manager.CurrentSessionChanged -= _onCurrentChanged;
            _manager.SessionsChanged -= _onSessionsChanged;
            _manager = null;
        }
    }

    private void QueueRefresh()
    {
        if (Interlocked.Exchange(ref _refreshQueued, 1) == 1) return;
        _ = Task.Run(async () =>
        {
            await Task.Delay(60); // let bursts of events settle
            Volatile.Write(ref _refreshQueued, 0);
            try { await RefreshAsync(); }
            catch (Exception ex) { _log.LogDebug(ex, "Media refresh failed"); }
        });
    }

    private void Attach(Session? session)
    {
        if (ReferenceEquals(session, _session)) return;
        if (_session is not null)
        {
            _session.MediaPropertiesChanged -= _onProps;
            _session.PlaybackInfoChanged -= _onPlayback;
            _session.TimelinePropertiesChanged -= _onTimeline;
        }
        _session = session;
        if (session is not null)
        {
            session.MediaPropertiesChanged += _onProps;
            session.PlaybackInfoChanged += _onPlayback;
            session.TimelinePropertiesChanged += _onTimeline;
        }
    }

    private Session? Pick(IReadOnlyList<Session> sessions)
    {
        if (_pinnedAppId is not null && sessions.FirstOrDefault(s => s.SourceAppUserModelId == _pinnedAppId) is { } pinned) return pinned;
        return _manager?.GetCurrentSession() ?? sessions.FirstOrDefault();
    }

    private async Task RefreshAsync()
    {
        if (_manager is null) return;
        await _refreshLock.WaitAsync();
        try
        {
            var sessions = _manager.GetSessions();
            var sources = sessions
                .Select(s => s.SourceAppUserModelId)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Select(id => new MediaSource(id, AppName(id)))
                .ToList();

            var session = Pick(sessions);
            // Session objects are re-projected per call; match on app id to keep our subscription stable.
            if (session is not null && _session is not null && session.SourceAppUserModelId == _session.SourceAppUserModelId)
                session = _session;
            Attach(session);

            if (session is null) { Publish(MediaState.None(sources)); return; }

            GlobalSystemMediaTransportControlsSessionMediaProperties? props = null;
            try { props = await session.TryGetMediaPropertiesAsync(); }
            catch (Exception ex) { _log.LogDebug(ex, "TryGetMediaPropertiesAsync failed"); }

            var playback = session.GetPlaybackInfo();
            var timeline = session.GetTimelineProperties();
            var controls = playback.Controls;

            var status = playback.PlaybackStatus switch
            {
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing => "playing",
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused => "paused",
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped => "stopped",
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Changing => "changing",
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Opened => "stopped",
                _ => "closed",
            };

            var duration = Math.Max(0, (timeline.EndTime - timeline.StartTime).TotalSeconds);
            var position = Math.Max(0, (timeline.Position - timeline.StartTime).TotalSeconds);
            if (status == "playing" && timeline.LastUpdatedTime.Year > 2000)
                position += Math.Max(0, (DateTimeOffset.Now - timeline.LastUpdatedTime).TotalSeconds);
            if (duration > 0) position = Math.Min(position, duration);

            var appId = session.SourceAppUserModelId;
            var artKey = $"{appId}|{props?.Title}|{props?.Artist}|{props?.AlbumTitle}";
            if (artKey != _artFor)
            {
                _artFor = artKey;
                _artPath = await ReadThumbnailAsync(props);
            }

            Publish(new MediaState(
                HasSession: true,
                Source: new MediaSource(appId, AppName(appId)),
                Title: NullIfEmpty(props?.Title),
                Artist: NullIfEmpty(props?.Artist) ?? NullIfEmpty(props?.AlbumArtist),
                Album: NullIfEmpty(props?.AlbumTitle),
                Artwork: _artPath,
                Status: status,
                Position: Math.Round(position, 2),
                Duration: Math.Round(duration, 2),
                PositionAt: DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                CanPlay: controls.IsPlayEnabled,
                CanPause: controls.IsPauseEnabled,
                CanNext: controls.IsNextEnabled,
                CanPrevious: controls.IsPreviousEnabled,
                CanSeek: controls.IsPlaybackPositionEnabled && duration > 0,
                CanShuffle: controls.IsShuffleEnabled,
                CanRepeat: controls.IsRepeatEnabled,
                Shuffle: playback.IsShuffleActive,
                Repeat: playback.AutoRepeatMode switch
                {
                    MediaPlaybackAutoRepeatMode.Track => "track",
                    MediaPlaybackAutoRepeatMode.List => "list",
                    MediaPlaybackAutoRepeatMode.None => "none",
                    _ => null,
                },
                Sessions: sources));
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    private async Task<string?> ReadThumbnailAsync(GlobalSystemMediaTransportControlsSessionMediaProperties? props)
    {
        if (props?.Thumbnail is null) return null;
        try
        {
            using var stream = await props.Thumbnail.OpenReadAsync();
            await using var input = stream.AsStreamForRead();
            using var ms = new MemoryStream();
            await input.CopyToAsync(ms);
            return _assets.Put(ms.ToArray(), string.IsNullOrEmpty(stream.ContentType) ? null : stream.ContentType);
        }
        catch (Exception ex)
        {
            _log.LogDebug(ex, "Couldn't read album art");
            return null;
        }
    }

    public override async Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        var s = _session;

        // With no media session, fall back to the hardware media keys so play/next still do something.
        if (s is null)
        {
            switch (action)
            {
                case "playPause" or "play" or "pause": KeyInput.Tap(KeyInput.VK_MEDIA_PLAY_PAUSE); return null;
                case "next": KeyInput.Tap(KeyInput.VK_MEDIA_NEXT_TRACK); return null;
                case "previous": KeyInput.Tap(KeyInput.VK_MEDIA_PREV_TRACK); return null;
                case "selectSession": break;
                default: throw new PanelActionException("Nothing is playing on the PC.");
            }
        }

        bool ok;
        switch (action)
        {
            case "playPause": ok = await s!.TryTogglePlayPauseAsync(); break;
            case "play": ok = await s!.TryPlayAsync(); break;
            case "pause": ok = await s!.TryPauseAsync(); break;
            case "next": ok = await s!.TrySkipNextAsync(); break;
            case "previous": ok = await s!.TrySkipPreviousAsync(); break;
            case "seek":
                var start = s!.GetTimelineProperties().StartTime;
                ok = await s.TryChangePlaybackPositionAsync((start + TimeSpan.FromSeconds(Math.Max(0, args.Double("seconds")))).Ticks);
                break;
            case "shuffle":
                ok = await s!.TryChangeShuffleActiveAsync(args.Bool("on", !(s.GetPlaybackInfo().IsShuffleActive ?? false)));
                break;
            case "repeat":
                var mode = args.OptionalString("mode") switch
                {
                    "track" => MediaPlaybackAutoRepeatMode.Track,
                    "list" => MediaPlaybackAutoRepeatMode.List,
                    "none" => MediaPlaybackAutoRepeatMode.None,
                    _ => s!.GetPlaybackInfo().AutoRepeatMode switch
                    {
                        MediaPlaybackAutoRepeatMode.None => MediaPlaybackAutoRepeatMode.List,
                        MediaPlaybackAutoRepeatMode.List => MediaPlaybackAutoRepeatMode.Track,
                        _ => MediaPlaybackAutoRepeatMode.None,
                    },
                };
                ok = await s!.TryChangeAutoRepeatModeAsync(mode);
                break;
            case "selectSession":
                _pinnedAppId = args.String("appId");
                ok = true;
                break;
            default:
                throw UnknownAction(action);
        }

        QueueRefresh();
        if (!ok) throw new PanelActionException($"{AppName(s?.SourceAppUserModelId ?? "The player")} didn't accept that command.");
        return null;
    }

    /// <summary>"SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify" → "Spotify"; "msedge.exe" → "Microsoft Edge".</summary>
    private string AppName(string appId)
    {
        lock (_appNames)
        {
            if (_appNames.TryGetValue(appId, out var cached)) return cached;
            return _appNames[appId] = ResolveAppName(appId);
        }
    }

    private static string ResolveAppName(string appId)
    {
        try
        {
            var info = Windows.ApplicationModel.AppInfo.GetFromAppUserModelId(appId);
            if (!string.IsNullOrWhiteSpace(info?.DisplayInfo?.DisplayName)) return info.DisplayInfo.DisplayName;
        }
        catch { /* not a packaged app */ }

        var exe = appId.Contains('!') ? appId[(appId.LastIndexOf('!') + 1)..] : appId;
        exe = Path.GetFileNameWithoutExtension(exe);
        try
        {
            foreach (var p in Process.GetProcessesByName(exe))
            {
                using (p)
                {
                    var path = Native.ProcessImagePath((uint)p.Id);
                    var description = path is null ? null : FileVersionInfo.GetVersionInfo(path).FileDescription;
                    if (!string.IsNullOrWhiteSpace(description)) return description!;
                }
            }
        }
        catch { }
        return exe.Length > 0 ? char.ToUpperInvariant(exe[0]) + exe[1..] : appId;
    }

    private static string? NullIfEmpty(string? s) => string.IsNullOrWhiteSpace(s) ? null : s;
}
