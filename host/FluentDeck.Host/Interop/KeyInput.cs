using FluentDeck.Core.Deck;
using FluentDeck.Core.Panels;
using static FluentDeck.Host.Interop.Native;

namespace FluentDeck.Host.Interop;

/// <summary>Synthesizes keystrokes with SendInput. Note: Windows won't let a normal app send input
/// to an elevated (admin) window — run FluentDeck elevated if you need that.</summary>
internal static class KeyInput
{
    public const ushort VK_MEDIA_NEXT_TRACK = 0xB0, VK_MEDIA_PREV_TRACK = 0xB1, VK_MEDIA_PLAY_PAUSE = 0xB3;

    private static readonly Dictionary<string, ushort> Keys = BuildKeyMap();

    private static readonly HashSet<ushort> Extended =
    [
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, // PgUp PgDn End Home arrows Ins Del
        0x5B, 0x5C, 0x5D, 0x6F, 0x90, 0x2C,                         // Win, Apps, Num /, NumLock, PrtSc
        0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xAB, 0xAC,                   // browser keys
        0xAD, 0xAE, 0xAF, 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7,
    ];

    public static void SendChords(IReadOnlyList<KeyChord> chords)
    {
        foreach (var chord in chords)
        {
            var mods = chord.Modifiers.Select(Vk).ToList();
            var key = Vk(chord.Key);
            var inputs = new List<INPUT>();
            foreach (var m in mods) inputs.Add(Key(m, up: false));
            inputs.Add(Key(key, up: false));
            inputs.Add(Key(key, up: true));
            for (var i = mods.Count - 1; i >= 0; i--) inputs.Add(Key(mods[i], up: true));
            Send(inputs);
            if (chords.Count > 1) Thread.Sleep(40);
        }
    }

    public static void Tap(ushort vk) => Send([Key(vk, false), Key(vk, true)]);

    public static void TypeText(string text)
    {
        var inputs = new List<INPUT>();
        foreach (var c in text.Replace("\r\n", "\n"))
        {
            if (c == '\n') { inputs.Add(Key(0x0D, false)); inputs.Add(Key(0x0D, true)); continue; }
            inputs.Add(Unicode(c, false));
            inputs.Add(Unicode(c, true));
        }
        // Chunk so very long snippets don't overflow the input queue.
        foreach (var chunk in inputs.Chunk(200)) { Send(chunk); Thread.Sleep(5); }
    }

    private static ushort Vk(string name) =>
        Keys.TryGetValue(name, out var vk) ? vk : throw new PanelActionException($"Unknown key '{name}' in deck.json");

    private static INPUT Key(ushort vk, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = (up ? KEYEVENTF_KEYUP : 0) | (Extended.Contains(vk) ? KEYEVENTF_EXTENDEDKEY : 0) } },
    };

    private static INPUT Unicode(char c, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = 0, wScan = c, dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0) } },
    };

    private static void Send(IEnumerable<INPUT> inputs)
    {
        var arr = inputs.ToArray();
        var sent = SendInput((uint)arr.Length, arr, System.Runtime.InteropServices.Marshal.SizeOf<INPUT>());
        if (sent != arr.Length)
            throw new PanelActionException("Windows blocked the keystrokes (the active window may be running as administrator).");
    }

    private static Dictionary<string, ushort> BuildKeyMap()
    {
        var m = new Dictionary<string, ushort>(StringComparer.OrdinalIgnoreCase)
        {
            ["ctrl"] = 0x11, ["shift"] = 0x10, ["alt"] = 0x12, ["win"] = 0x5B,
            ["enter"] = 0x0D, ["return"] = 0x0D, ["esc"] = 0x1B, ["escape"] = 0x1B, ["tab"] = 0x09,
            ["space"] = 0x20, ["backspace"] = 0x08, ["delete"] = 0x2E, ["del"] = 0x2E,
            ["insert"] = 0x2D, ["ins"] = 0x2D, ["home"] = 0x24, ["end"] = 0x23,
            ["pageup"] = 0x21, ["pgup"] = 0x21, ["pagedown"] = 0x22, ["pgdn"] = 0x22,
            ["up"] = 0x26, ["down"] = 0x28, ["left"] = 0x25, ["right"] = 0x27,
            ["printscreen"] = 0x2C, ["prtsc"] = 0x2C, ["pause"] = 0x13, ["capslock"] = 0x14,
            ["numlock"] = 0x90, ["scrolllock"] = 0x91, ["apps"] = 0x5D, ["menu"] = 0x5D,
            ["volumeup"] = 0xAF, ["volumedown"] = 0xAE, ["volumemute"] = 0xAD,
            ["playpause"] = 0xB3, ["mediaplaypause"] = 0xB3, ["nexttrack"] = 0xB0, ["medianext"] = 0xB0,
            ["prevtrack"] = 0xB1, ["mediaprev"] = 0xB1, ["mediastop"] = 0xB2,
            ["."] = 0xBE, ["period"] = 0xBE, [","] = 0xBC, ["comma"] = 0xBC,
            ["-"] = 0xBD, ["minus"] = 0xBD, ["="] = 0xBB, ["plus"] = 0xBB, ["equals"] = 0xBB,
            [";"] = 0xBA, ["semicolon"] = 0xBA, ["/"] = 0xBF, ["slash"] = 0xBF, ["`"] = 0xC0, ["backtick"] = 0xC0,
            ["["] = 0xDB, ["\\"] = 0xDC, ["backslash"] = 0xDC, ["]"] = 0xDD, ["'"] = 0xDE, ["quote"] = 0xDE,
        };
        for (var c = 'a'; c <= 'z'; c++) m[c.ToString()] = (ushort)char.ToUpperInvariant(c);
        for (var d = 0; d <= 9; d++) { m[d.ToString()] = (ushort)('0' + d); m[$"num{d}"] = (ushort)(0x60 + d); }
        for (var f = 1; f <= 24; f++) m[$"f{f}"] = (ushort)(0x6F + f);
        return m;
    }
}
