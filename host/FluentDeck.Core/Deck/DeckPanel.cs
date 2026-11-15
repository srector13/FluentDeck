using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Core.Deck;

/// <summary>The Stream Deck half: pages of buttons defined in deck.json, hot-reloaded on save.</summary>
public sealed class DeckPanel : PanelProvider, IDisposable
{
    private readonly HostPaths _paths;
    private readonly AssetStore _assets;
    private readonly IDeckActionExecutor _executor;
    private readonly IServiceProvider _services;
    private readonly ILogger<DeckPanel> _log;
    private FileSystemWatcher? _watcher;
    private Timer? _debounce;
    private DeckConfig _config = new();
    private Dictionary<string, DeckButton> _buttons = new();
    private string? _error;

    public DeckPanel(HostPaths paths, AssetStore assets, IDeckActionExecutor executor, IServiceProvider services, ILogger<DeckPanel> log)
    {
        _paths = paths; _assets = assets; _executor = executor; _services = services; _log = log;
    }

    public override PanelDescriptor Descriptor { get; } =
        new("deck", "Deck", "square.grid.3x3", 1, ["press", "reload"]);

    public static readonly JsonSerializerOptions ConfigJson = new(JsonSerializerDefaults.Web)
    {
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
    };

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
            default:
                throw UnknownAction(action);
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
            case "launch" or "url" or "keys" or "text":
                await _executor.ExecuteAsync(action, ct);
                break;
            default:
                throw new PanelActionException($"Unknown deck action type '{action.Type}'");
        }
    }

    private void Reload()
    {
        try
        {
            var text = ReadShared(_paths.DeckFile);
            _config = JsonSerializer.Deserialize<DeckConfig>(text, ConfigJson) ?? new DeckConfig();
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

    private void PublishState()
    {
        var buttons = new Dictionary<string, DeckButton>();
        var pages = new List<object>();
        var pageIndex = 0;
        foreach (var page in _config.Pages)
        {
            var pageId = string.IsNullOrWhiteSpace(page.Id) ? $"page{pageIndex}" : page.Id;
            pageIndex++;
            var views = new List<object>();
            var i = 0;
            foreach (var b in page.Buttons)
            {
                var id = $"{pageId}/{(string.IsNullOrWhiteSpace(b.Id) ? i.ToString() : b.Id)}";
                i++;
                buttons[id] = b;
                views.Add(new
                {
                    id,
                    label = b.Label,
                    symbol = b.Symbol,
                    symbolOn = b.SymbolOn,
                    icon = b.Icon is { Length: > 0 } path ? _assets.Put(SafeIcon(path), "image/png") : null,
                    style = b.Style ?? "standard",
                    state = b.State is null ? null : new { topic = b.State.Topic, path = b.State.Path, equals = b.State.Is },
                    kind = b.Action?.Type ?? "none",
                });
            }
            pages.Add(new { id = pageId, title = string.IsNullOrWhiteSpace(page.Title) ? pageId : page.Title, columns = page.Columns, buttons = views });
        }
        _buttons = buttons;
        Publish(new { pages, error = _error });
    }

    private byte[]? SafeIcon(string path)
    {
        try { return _executor.TryGetIcon(Environment.ExpandEnvironmentVariables(path)); }
        catch (Exception ex) { _log.LogDebug(ex, "No icon for {Path}", path); return null; }
    }

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
