namespace FluentDeck.Core.Deck;

/// <summary>A parsed hotkey such as Win+Shift+S. Key names are lower-case.</summary>
public sealed record KeyChord(IReadOnlyList<string> Modifiers, string Key)
{
    private static readonly Dictionary<string, string> ModifierAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ctrl"] = "ctrl", ["control"] = "ctrl",
        ["shift"] = "shift",
        ["alt"] = "alt", ["option"] = "alt",
        ["win"] = "win", ["windows"] = "win", ["meta"] = "win", ["super"] = "win", ["cmd"] = "win",
    };

    /// <summary>Parse "Ctrl+Shift+Esc" or a space-separated sequence "Ctrl+K Ctrl+S".</summary>
    public static IReadOnlyList<KeyChord> ParseSequence(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new FormatException("Empty key sequence");
        return text.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(Parse).ToList();
    }

    public static KeyChord Parse(string chord)
    {
        // "Ctrl++" means Ctrl and the plus key.
        var parts = chord.EndsWith("++")
            ? chord[..^2].Split('+', StringSplitOptions.RemoveEmptyEntries).Append("plus").ToArray()
            : chord.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0) throw new FormatException($"Empty chord in '{chord}'");

        // Everything before the last part must be a modifier; the last part is the key.
        // A lone modifier ("Win") is a valid chord: press and release it.
        var mods = new List<string>();
        foreach (var part in parts[..^1])
        {
            if (!ModifierAliases.TryGetValue(part, out var m))
                throw new FormatException($"'{part}' isn't a modifier (in '{chord}')");
            if (!mods.Contains(m)) mods.Add(m);
        }
        var last = parts[^1];
        var key = ModifierAliases.TryGetValue(last, out var lastMod) ? lastMod : last.ToLowerInvariant();
        return new KeyChord(mods, key);
    }

    public override string ToString() => string.Join("+", Modifiers.Append(Key));
}
