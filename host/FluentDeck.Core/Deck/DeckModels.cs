using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace FluentDeck.Core.Deck;

// deck.json lives in %LOCALAPPDATA%\FluentDeck and is hot-reloaded on save.
// Buttons only ever run actions defined here — the iPad can press a button, never send a command.

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
    /// <summary>Path to an .exe/.lnk/file on the PC; its Windows icon is shown instead of the symbol.</summary>
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

/// <summary>Executes the platform-specific action types (launch, url, keys, text).</summary>
public interface IDeckActionExecutor
{
    Task ExecuteAsync(DeckAction action, CancellationToken ct);

    /// <summary>PNG bytes of the Windows icon for a file, or null.</summary>
    byte[]? TryGetIcon(string path);
}
