using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace FluentDeck.Core.Hosting;

/// <summary>Content-addressed, in-memory store for album art and app icons, served at /assets/{key}.
/// Panels put bytes in and publish the returned path in their state.</summary>
public sealed class AssetStore
{
    private sealed record Entry(byte[] Data, string ContentType, long Touched);

    private readonly ConcurrentDictionary<string, Entry> _entries = new();
    private const int MaxEntries = 600;
    private const int MaxBytes = 2 * 1024 * 1024;

    /// <returns>A path like <c>/assets/3f9a…</c>, or null if the data is empty or too large.</returns>
    public string? Put(byte[]? data, string? contentType = null)
    {
        if (data is null || data.Length == 0 || data.Length > MaxBytes) return null;
        var key = Convert.ToHexStringLower(SHA1.HashData(data))[..20];
        _entries[key] = new Entry(data, contentType ?? Sniff(data), Environment.TickCount64);
        if (_entries.Count > MaxEntries) Trim();
        return "/assets/" + key;
    }

    public bool TryGet(string key, out byte[] data, out string contentType)
    {
        if (_entries.TryGetValue(key, out var e))
        {
            _entries[key] = e with { Touched = Environment.TickCount64 };
            data = e.Data; contentType = e.ContentType;
            return true;
        }
        data = []; contentType = "";
        return false;
    }

    private void Trim()
    {
        foreach (var old in _entries.OrderBy(kv => kv.Value.Touched).Take(_entries.Count - MaxEntries + 50).ToList())
            _entries.TryRemove(old.Key, out _);
    }

    private static string Sniff(byte[] d) =>
        d.Length > 3 && d[0] == 0x89 && d[1] == 0x50 ? "image/png" :
        d.Length > 2 && d[0] == 0xFF && d[1] == 0xD8 ? "image/jpeg" :
        d.Length > 11 && d[8] == 0x57 && d[9] == 0x45 && d[10] == 0x42 && d[11] == 0x50 ? "image/webp" :
        "application/octet-stream";
}
