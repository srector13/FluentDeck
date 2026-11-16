using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace FluentDeck.Core.Deck;

// deck.json lives in %LOCALAPPDATA%\FluentDeck and is hot-reloaded on save.
// Buttons only ever run actions defined here. By default the iPad can press a button but never
// define one; turning on "allowDeckEditing" in host.json (the tray menu does it) lets paired
// devices edit this file through the deck panel's edit actions.

public sealed class DeckConfig
{
    public List<DeckPage> Pages { get; set; } = [];
}

public sealed class DeckPage
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    /// <summary>Optional fixed column count; otherwise the iPad fits as many as the widget allows.</summary>
    public int? Columns { get; set; }
    public List<DeckButton> Buttons { get; set; } = [];
}

public sealed class DeckButton
{
    public string Id { get; set; } = "";
    public string Label { get; set; } = "";
    /// <summary>SF Symbol name rendered on the iPad (e.g. "music.note", "lock").</summary>
    public string? Symbol { get; set; }
    /// <summary>Symbol to show while <see cref="State"/> is on.</summary>
    public string? SymbolOn { get; set; }
    /// <summary>Shown instead of the symbol. Either a path to an .exe/.lnk/file on the PC (its Windows
    /// icon is used) or an image file (.png/.jpg), absolute or relative to the data folder.</summary>
    public string? Icon { get; set; }
    /// <summary>"standard" (default) or "accent".</summary>
    public string? Style { get; set; }
    /// <summary>Optional live binding: the button lights up when topic.path equals the value.</summary>
    public DeckStateBinding? State { get; set; }
    public DeckAction? Action { get; set; }
}

public sealed class DeckStateBinding
{
    public string Topic { get; set; } = "";
    /// <summary>Dot path into the topic state, e.g. "input.muted" or "status".</summary>
    public string Path { get; set; } = "";
    /// <summary>Value that means "on". Defaults to true.</summary>
    [JsonPropertyName("equals")]
    public JsonNode? Is { get; set; }
}

public sealed class DeckAction
{
    /// <summary>launch | url | keys | text | builtin | sequence | delay</summary>
    public string Type { get; set; } = "";

    // launch / url
    public string? Target { get; set; }
    public string? Arguments { get; set; }
    public string? WorkingDirectory { get; set; }
    public bool Hidden { get; set; }

    // keys: "Win+Shift+S", or several chords separated by spaces: "Ctrl+K Ctrl+S"
    public string? Keys { get; set; }

    // text: typed as Unicode keystrokes
    public string? Text { get; set; }

    // builtin: call any host panel action, e.g. panel "audio", action "toggleMicMute"
    public string? Panel { get; set; }
    public string? Action { get; set; }
    public JsonObject? Args { get; set; }

    // sequence (Stream Deck "multi action") and delay
    public List<DeckAction>? Steps { get; set; }
    public int? Ms { get; set; }
}

/// <summary>An installed app the iPad can offer when a key is set to launch something.</summary>
/// <param name="Name">Display name.</param>
/// <param name="Path">What a "launch" action should target (and what its icon comes from).</param>
public sealed record DeckApp(string Name, string Path);

/// <summary>Executes the platform-specific action types (launch, url, keys, text).</summary>
public interface IDeckActionExecutor
{
    Task ExecuteAsync(DeckAction action, CancellationToken ct);

    /// <summary>PNG bytes of the Windows icon for a file, or null.</summary>
    byte[]? TryGetIcon(string path);

    /// <summary>Apps installed on this PC, for the key editor's app picker.</summary>
    IReadOnlyList<DeckApp> ListApps() => [];
}
