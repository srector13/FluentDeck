using System.ComponentModel;
using System.Diagnostics;
using System.Drawing.Imaging;
using FluentDeck.Core.Deck;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;

namespace FluentDeck.Host.Panels;

/// <summary>Runs deck actions on Windows: launch apps, open URLs/URIs, send hotkeys, type text.</summary>
internal sealed class WindowsDeckExecutor : IDeckActionExecutor
{
    public Task ExecuteAsync(DeckAction action, CancellationToken ct)
    {
        switch (action.Type)
        {
            case "launch":
                Start(new ProcessStartInfo(ResolvePath(action.Target ?? throw new PanelActionException("launch needs \"target\"")))
                {
                    Arguments = Expand(action.Arguments) ?? "",
                    WorkingDirectory = Expand(action.WorkingDirectory) ?? "",
                    UseShellExecute = true,
                    WindowStyle = action.Hidden ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal,
                });
                break;
            case "url":
                Start(new ProcessStartInfo(action.Target ?? throw new PanelActionException("url needs \"target\"")) { UseShellExecute = true });
                break;
            case "keys":
                KeyInput.SendChords(KeyChord.ParseSequence(action.Keys ?? throw new PanelActionException("keys needs \"keys\"")));
                break;
            case "text":
                KeyInput.TypeText(action.Text ?? "");
                break;
            default:
                throw new PanelActionException($"Unsupported action '{action.Type}'");
        }
        return Task.CompletedTask;
    }

    public byte[]? TryGetIcon(string path) => IconExtractor.Png(ResolvePath(path), 64);

    /// <summary>The Start menu's shortcuts, for all users and this one. Launching the shortcut itself
    /// keeps its arguments and working folder. Store apps have no shortcut file, so they aren't listed.</summary>
    public IReadOnlyList<DeckApp> ListApps()
    {
        string[] skip = ["uninstall", "readme", "read me", "help", "documentation", "website", "license", "release notes"];
        var apps = new Dictionary<string, DeckApp>(StringComparer.OrdinalIgnoreCase);
        foreach (var folder in new[] { Environment.SpecialFolder.Programs, Environment.SpecialFolder.CommonPrograms })
        {
            var root = Environment.GetFolderPath(folder);
            if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
            try
            {
                var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true };
                foreach (var shortcut in Directory.EnumerateFiles(root, "*.lnk", options))
                {
                    var name = Path.GetFileNameWithoutExtension(shortcut);
                    if (skip.Any(word => name.Contains(word, StringComparison.OrdinalIgnoreCase))) continue;
                    apps.TryAdd(name, new DeckApp(name, shortcut));
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* skip that folder */ }
        }
        return apps.Values.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    private static void Start(ProcessStartInfo info)
    {
        try { Process.Start(info)?.Dispose(); }
        catch (Win32Exception ex) { throw new PanelActionException($"Couldn't open {info.FileName}: {ex.Message}"); }
    }

    private static string? Expand(string? s) => s is null ? null : Environment.ExpandEnvironmentVariables(s);

    /// <summary>"explorer.exe" → C:\Windows\explorer.exe, using PATH like the shell does.</summary>
    internal static string ResolvePath(string path)
    {
        path = Environment.ExpandEnvironmentVariables(path);
        if (Path.IsPathRooted(path) || File.Exists(path)) return path;
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir.Trim(), path);
            if (File.Exists(candidate)) return candidate;
            foreach (var ext in new[] { ".exe", ".cmd", ".bat", ".com" })
                if (File.Exists(candidate + ext)) return candidate + ext;
        }
        return path;
    }
}

internal static class IconExtractor
{
    private static readonly Dictionary<string, byte[]?> Cache = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>PNG of a file's Windows icon at roughly <paramref name="size"/> px, alpha preserved.</summary>
    public static byte[]? Png(string? path, int size)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
        lock (Cache)
        {
            if (Cache.TryGetValue(path, out var cached)) return cached;
            byte[]? png = null;
            Icon? icon = null;
            // A program's own icon at the size we want; a shortcut or document falls back to its associated icon.
            try { icon = Icon.ExtractIcon(path, 0, size); } catch { /* not an icon resource */ }
            try { icon ??= Icon.ExtractAssociatedIcon(path); } catch { /* no association */ }
            try
            {
                if (icon is not null)
                {
                    using var bmp = icon.ToBitmap();
                    using var ms = new MemoryStream();
                    bmp.Save(ms, ImageFormat.Png);
                    png = ms.ToArray();
                }
            }
            catch { /* some icons can't be drawn */ }
            finally { icon?.Dispose(); }
            return Cache[path] = png;
        }
    }
}
