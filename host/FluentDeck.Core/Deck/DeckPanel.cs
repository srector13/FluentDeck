using System.Reflection;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Core.Deck;

/// <summary>The Stream Deck half: pages of buttons defined in deck.json, hot-reloaded on save.
/// When the host allows it, paired devices can also edit the file through the edit actions.</summary>
public sealed class DeckPanel : PanelProvider, IDisposable
{
    private static readonly string[] EditActions =
        ["getButton", "saveButton", "deleteButton", "moveButton", "addPage", "renamePage", "deletePage", "listApps", "uploadIcon"];
    private static readonly HashSet<string> ActionTypes = ["launch", "focus", "url", "keys", "text", "builtin", "sequence", "delay"];
    private const int MaxIconBytes = 180_000; // fits one WebSocket message as base64

    private readonly HostPaths _paths;
    private readonly HostSettings _settings;
    private readonly AssetStore _assets;
    private readonly IDeckActionExecutor _executor;
    private readonly IServiceProvider _services;
    private readonly ILogger<DeckPanel> _log;
    private readonly object _gate = new();
    private FileSystemWatcher? _watcher;
    private Timer? _debounce;
    private DeckConfig _config = new();
    private Dictionary<string, DeckButton> _buttons = new();
    private string? _error;
    private (DateTime At, object[] Apps)? _apps;

    public DeckPanel(HostPaths paths, HostSettings settings, AssetStore assets, IDeckActionExecutor executor, IServiceProvider services, ILogger<DeckPanel> log)
    {
        _paths = paths; _settings = settings; _assets = assets; _executor = executor; _services = services; _log = log;
    }

    public override PanelDescriptor Descriptor { get; } =
        new("deck", "Deck", "square.grid.3x3", 2, ["press", "reload", .. EditActions]);

    public static readonly JsonSerializerOptions ConfigJson = new(JsonSerializerDefaults.Web)
    {
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
    };

    /// <summary>How edits are written back: no nulls or default values, and readable text.</summary>
    private static readonly JsonSerializerOptions WriteJson = new(ConfigJson)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingDefault,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private const string FileHeader = """
        // FluentDeck buttons. Edit them on the iPad (Customize, then tap a key) or here; saving this
        // file updates the iPad instantly.
        //
        // "symbol"  : any SF Symbol name
        // "icon"    : an .exe/.lnk on this PC (shows its Windows icon) or a .png/.jpg image
        // "style"   : "standard" | "accent" (always lit; any button lights up while its "state" is on)
        // "state"   : light the button up when a live value matches, e.g. mic muted
        // "action"  : launch {target, arguments, workingDirectory, hidden} | url {target} | keys {keys}
        //             | text {text} | builtin {panel, action, args} | sequence {steps} | delay {ms}

        """;

    public override Task StartAsync(CancellationToken ct)
    {
        if (!File.Exists(_paths.DeckFile)) File.WriteAllText(_paths.DeckFile, DefaultDeckJson());
        Reload();

        _debounce = new Timer(_ => Reload());
        _watcher = new FileSystemWatcher(_paths.Root, Path.GetFileName(_paths.DeckFile))
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
            EnableRaisingEvents = true,
        };
        void Kick(object? s, FileSystemEventArgs e) => _debounce?.Change(300, Timeout.Infinite);
        _watcher.Changed += Kick;
        _watcher.Created += Kick;
        _watcher.Renamed += (s, e) => Kick(s, e);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    public void Dispose()
    {
        _watcher?.Dispose(); _watcher = null;
        _debounce?.Dispose(); _debounce = null;
    }

    /// <summary>Call after <see cref="HostSettings.AllowDeckEditing"/> changes so devices hear about it.</summary>
    public void SettingsChanged()
    {
        lock (_gate) PublishState();
    }

    public override async Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        switch (action)
        {
            case "press":
                var id = args.String("buttonId");
                if (!_buttons.TryGetValue(id, out var button)) throw new PanelActionException("That button no longer exists — deck.json changed.");
                if (button.Action is null) return null;
                await RunAsync(button.Action, ct, depth: 0);
                return null;
            case "reload":
                Reload();
                return null;
        }

        if (!EditActions.Contains(action)) throw UnknownAction(action);
        if (!_settings.AllowDeckEditing)
            throw new PanelActionException("Editing keys is turned off on this PC. Turn on “Allow editing keys from the iPad” in the FluentDeck tray menu.");

        lock (_gate)
        {
            return action switch
            {
                "getButton" => GetButton(args),
                "listApps" => ListApps(),
                "uploadIcon" => UploadIcon(args),
                _ => Edit(action, args),
            };
        }
    }

    private async Task RunAsync(DeckAction action, CancellationToken ct, int depth)
    {
        if (depth > 8) throw new PanelActionException("Sequence nested too deeply");
        switch (action.Type.ToLowerInvariant())
        {
            case "builtin":
                var registry = _services.GetRequiredService<PanelRegistry>();
                await registry.InvokeAsync(action.Panel ?? throw new PanelActionException("builtin action needs \"panel\""),
                                           action.Action ?? throw new PanelActionException("builtin action needs \"action\""),
                                           action.Args?.DeepClone() as JsonObject, ct);
                break;
            case "sequence":
                foreach (var step in action.Steps ?? []) await RunAsync(step, ct, depth + 1);
                break;
            case "delay":
                await Task.Delay(Math.Clamp(action.Ms ?? 100, 0, 10_000), ct);
                break;
            case "launch" or "focus" or "url" or "keys" or "text":
                await _executor.ExecuteAsync(action, ct);
                break;
            default:
                throw new PanelActionException($"Unknown deck action type '{action.Type}'");
        }
    }

    // MARK: editing (all called under _gate, with editing allowed)

    private object GetButton(JsonObject args)
    {
        var (page, index) = Locate(args.String("buttonId"));
        var button = page.Buttons[index];
        return new
        {
            pageId = page.Id,
            index,
            count = page.Buttons.Count,
            button = JsonSerializer.SerializeToNode(button, WriteJson),
            iconAsset = IconAsset(button.Icon),
        };
    }

    private object ListApps()
    {
        if (_apps is { } cached && DateTime.UtcNow - cached.At < TimeSpan.FromMinutes(2)) return new { apps = cached.Apps };
        var apps = _executor.ListApps().Take(200)
            .Select(a => (object)new { name = a.Name, path = a.Path, icon = IconAsset(a.Path) })
            .ToArray();
        _apps = (DateTime.UtcNow, apps);
        return new { apps };
    }

    /// <summary>Stores an image the iPad chose as a key's icon under icons/ in the data folder.</summary>
    private object UploadIcon(JsonObject args)
    {
        byte[] data;
        try { data = Convert.FromBase64String(args.String("data")); }
        catch (FormatException) { throw new PanelActionException("That image didn't arrive intact."); }
        if (data.Length > MaxIconBytes) throw new PanelActionException("That image is too large for a key icon.");
        var extension = data.Length > 3 && data[0] == 0x89 && data[1] == 0x50 ? "png"
            : data.Length > 2 && data[0] == 0xFF && data[1] == 0xD8 ? "jpg"
            : throw new PanelActionException("Key icons must be PNG or JPEG images.");

        var folder = Path.Combine(_paths.Root, "icons");
        Directory.CreateDirectory(folder);
        var name = $"{Convert.ToHexStringLower(SHA1.HashData(data))[..16]}.{extension}";
        File.WriteAllBytes(Path.Combine(folder, name), data);
        return new { icon = $"icons/{name}", iconAsset = _assets.Put(data) };
    }

    private object? Edit(string action, JsonObject args)
    {
        if (_error is not null) throw new PanelActionException("deck.json has an error. Fix it on the PC before editing keys here.");
        object? result = null;
        switch (action)
        {
            case "saveButton":
            {
                var incoming = (args["button"] as JsonObject)?.Deserialize<DeckButton>(ConfigJson)
                               ?? throw new PanelActionException("Missing 'button'");
                Clean(incoming);
                if (args.OptionalString("buttonId") is { Length: > 0 } existingId)
                {
                    var (page, index) = Locate(existingId);
                    incoming.Id = page.Buttons[index].Id;
                    page.Buttons[index] = incoming;
                    result = new { buttonId = $"{page.Id}/{incoming.Id}" };
                }
                else
                {
                    var page = FindPage(args.String("pageId"));
                    if (page.Buttons.Count >= 64) throw new PanelActionException("That page is full.");
                    incoming.Id = Unique(Slug(incoming.Label, "key"), page.Buttons.Select(b => b.Id));
                    page.Buttons.Add(incoming);
                    result = new { buttonId = $"{page.Id}/{incoming.Id}" };
                }
                break;
            }
            case "deleteButton":
            {
                var (page, index) = Locate(args.String("buttonId"));
                page.Buttons.RemoveAt(index);
                break;
            }
            case "moveButton":
            {
                var (page, index) = Locate(args.String("buttonId"));
                var target = Math.Clamp(index + (int)args.Double("by"), 0, page.Buttons.Count - 1);
                var button = page.Buttons[index];
                page.Buttons.RemoveAt(index);
                page.Buttons.Insert(target, button);
                break;
            }
            case "addPage":
            {
                if (_config.Pages.Count >= 32) throw new PanelActionException("There are too many pages.");
                var title = CleanTitle(args.OptionalString("title")) ?? $"Page {_config.Pages.Count + 1}";
                var page = new DeckPage { Id = Unique(Slug(title, "page"), _config.Pages.Select(p => p.Id)), Title = title };
                _config.Pages.Add(page);
                result = new { pageId = page.Id };
                break;
            }
            case "renamePage":
                FindPage(args.String("pageId")).Title = CleanTitle(args.String("title")) ?? throw new PanelActionException("A page needs a name.");
                break;
            case "deletePage":
                if (_config.Pages.Count <= 1) throw new PanelActionException("The last page can't be deleted.");
                _config.Pages.Remove(FindPage(args.String("pageId")));
                break;
            default:
                throw UnknownAction(action);
        }

        File.WriteAllText(_paths.DeckFile, FileHeader + JsonSerializer.Serialize(_config, WriteJson) + Environment.NewLine);
        PublishState();
        return result;
    }

    /// <summary>Trim what the iPad sent and reject anything the deck couldn't run.</summary>
    private static void Clean(DeckButton b)
    {
        b.Label = (b.Label ?? "").Trim();
        if (b.Label.Length > 40) b.Label = b.Label[..40];
        b.Symbol = Blank(b.Symbol);
        b.SymbolOn = Blank(b.SymbolOn);
        b.Icon = Blank(b.Icon);
        b.Style = b.Style == "accent" ? "accent" : null;
        if (b.State is { } state && (string.IsNullOrWhiteSpace(state.Topic) || string.IsNullOrWhiteSpace(state.Path))) b.State = null;
        if (b.Action is { } action) Check(action, depth: 0);
    }

    private static void Check(DeckAction a, int depth)
    {
        if (depth > 8) throw new PanelActionException("Sequence nested too deeply");
        a.Type = (a.Type ?? "").Trim().ToLowerInvariant();
        if (!ActionTypes.Contains(a.Type)) throw new PanelActionException($"Unknown action type '{a.Type}'");
        switch (a.Type)
        {
            case "launch" or "url" or "focus":
                a.Target = Blank(a.Target) ?? throw new PanelActionException(a.Type == "url" ? "Enter a link to open." : "Choose an app or enter a path.");
                break;
            case "keys":
                try { _ = KeyChord.ParseSequence(a.Keys ?? ""); }
                catch (FormatException ex) { throw new PanelActionException($"That key combination isn't valid: {ex.Message}"); }
                break;
            case "builtin":
                if (Blank(a.Panel) is null || Blank(a.Action) is null) throw new PanelActionException("Choose what the key should control.");
                break;
            case "sequence":
                foreach (var step in a.Steps ?? []) Check(step, depth + 1);
                break;
        }
    }

    private static string? Blank(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    private static string? CleanTitle(string? s)
    {
        var title = Blank(s);
        return title is { Length: > 30 } ? title[..30] : title;
    }

    private DeckPage FindPage(string pageId) =>
        _config.Pages.FirstOrDefault(p => p.Id == pageId) ?? throw new PanelActionException("That page no longer exists.");

    private (DeckPage Page, int Index) Locate(string buttonId)
    {
        foreach (var page in _config.Pages)
        {
            if (!buttonId.StartsWith(page.Id + "/", StringComparison.Ordinal)) continue;
            var key = buttonId[(page.Id.Length + 1)..];
            var index = page.Buttons.FindIndex(b => b.Id == key);
            if (index >= 0) return (page, index);
        }
        throw new PanelActionException("That button no longer exists — deck.json changed.");
    }

    private static string Slug(string text, string fallback)
    {
        var chars = text.ToLowerInvariant().Select(c => char.IsAsciiLetterOrDigit(c) ? c : '-').ToArray();
        var slug = string.Join("-", new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
        return slug.Length == 0 ? fallback : slug.Length > 24 ? slug[..24].Trim('-') : slug;
    }

    private static string Unique(string wanted, IEnumerable<string> taken)
    {
        var used = taken.ToHashSet(StringComparer.Ordinal);
        if (!used.Contains(wanted)) return wanted;
        for (var n = 2; ; n++)
            if (!used.Contains($"{wanted}-{n}")) return $"{wanted}-{n}";
    }

    // MARK: loading and publishing

    private void Reload()
    {
        lock (_gate)
        {
            try
            {
                var text = ReadShared(_paths.DeckFile);
                _config = Normalize(JsonSerializer.Deserialize<DeckConfig>(text, ConfigJson) ?? new DeckConfig());
                _error = null;
                _log.LogInformation("Loaded deck.json: {Pages} page(s)", _config.Pages.Count);
            }
            catch (Exception ex) when (ex is JsonException or IOException)
            {
                // Keep the last good config; tell the iPad what's wrong.
                _error = $"deck.json: {ex.Message}";
                _log.LogWarning("deck.json is invalid: {Message}", ex.Message);
            }
            PublishState();
        }
    }

    /// <summary>Give every page and button an id that is unique where it lives, so edits can address
    /// them. A button without one takes its position, as before; ids are only written on an edit.</summary>
    private static DeckConfig Normalize(DeckConfig config)
    {
        var pageIds = new List<string>();
        for (var p = 0; p < config.Pages.Count; p++)
        {
            var page = config.Pages[p];
            page.Id = Unique(Blank(page.Id) ?? $"page{p}", pageIds);
            pageIds.Add(page.Id);

            var buttonIds = new List<string>();
            for (var b = 0; b < page.Buttons.Count; b++)
            {
                var button = page.Buttons[b];
                button.Id = Unique(Blank(button.Id) ?? b.ToString(), buttonIds);
                buttonIds.Add(button.Id);
            }
        }
        return config;
    }

    private void PublishState()
    {
        var buttons = new Dictionary<string, DeckButton>();
        var pages = new List<object>();
        foreach (var page in _config.Pages)
        {
            var views = new List<object>();
            foreach (var b in page.Buttons)
            {
                var id = $"{page.Id}/{b.Id}";
                buttons[id] = b;
                views.Add(new
                {
                    id,
                    label = b.Label,
                    symbol = b.Symbol,
                    symbolOn = b.SymbolOn,
                    icon = IconAsset(b.Icon),
                    // An image file fills the key like a Stream Deck icon; a program's icon sits on the tile.
                    iconFill = b.Icon is { } iconPath && IsImage(Environment.ExpandEnvironmentVariables(iconPath)),
                    style = b.Style ?? "standard",
                    state = b.State is null ? null : new { topic = b.State.Topic, path = b.State.Path, equals = b.State.Is },
                    kind = b.Action?.Type ?? "none",
                });
            }
            pages.Add(new { id = page.Id, title = string.IsNullOrWhiteSpace(page.Title) ? page.Id : page.Title, columns = page.Columns, buttons = views });
        }
        _buttons = buttons;
        Publish(new { pages, error = _error, editable = _settings.AllowDeckEditing });
    }

    private string? IconAsset(string? path) =>
        path is { Length: > 0 } ? _assets.Put(SafeIcon(path)) : null;

    private byte[]? SafeIcon(string path)
    {
        try
        {
            var expanded = Environment.ExpandEnvironmentVariables(path);
            // An image file is the icon itself; anything else lends its Windows icon.
            if (IsImage(expanded))
            {
                var file = Path.IsPathRooted(expanded) ? expanded : Path.Combine(_paths.Root, expanded);
                return File.Exists(file) && new FileInfo(file).Length <= 2 * 1024 * 1024 ? File.ReadAllBytes(file) : null;
            }
            return _executor.TryGetIcon(expanded);
        }
        catch (Exception ex) { _log.LogDebug(ex, "No icon for {Path}", path); return null; }
    }

    private static bool IsImage(string path) => Path.GetExtension(path).ToLowerInvariant() is ".png" or ".jpg" or ".jpeg";

    private static string ReadShared(string path)
    {
        // Editors may still hold the file open while saving; retry briefly.
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var reader = new StreamReader(fs);
                return reader.ReadToEnd();
            }
            catch (IOException) when (attempt < 5) { Thread.Sleep(80); }
        }
    }

    public static string DefaultDeckJson()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("FluentDeck.Core.Deck.deck.default.json")!;
        using var r = new StreamReader(s);
        return r.ReadToEnd();
    }
}
