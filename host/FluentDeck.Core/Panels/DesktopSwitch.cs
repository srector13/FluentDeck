using System.Text.Json.Nodes;

namespace FluentDeck.Core.Panels;

/// <summary>Works out a desktop switch: which desktop an action asks for, and how many steps left
/// (negative) or right (positive) that is from the current one. Shared by the Windows host and
/// the DevHost so both treat the arguments the same way.</summary>
public static class DesktopSwitch
{
    /// <summary>The 1-based desktop that <paramref name="action"/> asks for, clamped to the desktops
    /// that exist. "switch" takes <c>index</c> (1-based).</summary>
    public static int Target(string action, JsonObject args, int current, int count)
    {
        if (count < 1) throw new PanelActionException("Windows reported no desktops.");
        return action switch
        {
            "next" => Math.Min(count, Math.Max(current, 1) + 1),
            "previous" => Math.Max(1, Math.Max(current, 1) - 1),
            "switch" => Index(args, count),
            _ => throw new PanelActionException($"Unknown action '{action}'"),
        };
    }

    private static int Index(JsonObject args, int count)
    {
        var index = (int)Math.Round(args.Double("index"));
        if (index < 1 || index > count)
            throw new PanelActionException(count == 1
                ? "This PC has only one desktop. Add one with Win+Ctrl+D or Task View."
                : $"Desktop {index} doesn't exist; this PC has {count}.");
        return index;
    }
}
