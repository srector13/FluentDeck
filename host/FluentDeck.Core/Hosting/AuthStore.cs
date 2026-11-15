using System.Security.Cryptography;
using System.Text.Json;

namespace FluentDeck.Core.Hosting;

/// <summary>Where the host keeps its files: %LOCALAPPDATA%\FluentDeck on Windows.</summary>
public sealed class HostPaths
{
    public HostPaths(string? root = null)
    {
        Root = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FluentDeck");
        Directory.CreateDirectory(Root);
    }

    public string Root { get; }
    public string AuthFile => Path.Combine(Root, "devices.json");
    public string SettingsFile => Path.Combine(Root, "host.json");
    public string DeckFile => Path.Combine(Root, "deck.json");
}

/// <summary>Host settings (port, identity). Edit host.json to change the port.</summary>
public sealed class HostSettings
{
    public string HostId { get; set; } = Guid.NewGuid().ToString("N");
    public string? DisplayName { get; set; }
    public int Port { get; set; } = 47610;
    public bool AdvertiseBonjour { get; set; } = true;

    public string Name => string.IsNullOrWhiteSpace(DisplayName) ? Environment.MachineName : DisplayName!;
    public static string Version => typeof(HostSettings).Assembly.GetName().Version?.ToString(3) ?? "0.1.0";

    public static HostSettings Load(HostPaths paths)
    {
        HostSettings? s = null;
        try
        {
            if (File.Exists(paths.SettingsFile))
                s = JsonSerializer.Deserialize<HostSettings>(File.ReadAllText(paths.SettingsFile), Json);
        }
        catch { /* fall through to defaults */ }
        s ??= new HostSettings();
        File.WriteAllText(paths.SettingsFile, JsonSerializer.Serialize(s, Json));
        return s;
    }

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { WriteIndented = true };
}

public sealed record PairedDevice(string Name, string TokenHash, DateTimeOffset PairedAt, DateTimeOffset? LastSeen);

/// <summary>Pairing codes and long-lived device tokens. Only SHA-256 hashes of tokens are stored.</summary>
public sealed class AuthStore
{
    private readonly HostPaths _paths;
    private readonly object _gate = new();
    private List<PairedDevice> _devices;
    private string? _code;
    private DateTimeOffset _codeExpires;
    private int _codeAttempts;

    public static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(3);
    private const int MaxAttemptsPerCode = 5;

    public event Action<PairedDevice>? DevicePaired;

    public AuthStore(HostPaths paths)
    {
        _paths = paths;
        _devices = Load();
    }

    public IReadOnlyList<PairedDevice> Devices { get { lock (_gate) return _devices.ToList(); } }

    /// <summary>Start a pairing window and return the 6-digit code to show on the PC.</summary>
    public string BeginPairing(TimeSpan? lifetime = null, string? fixedCode = null)
    {
        lock (_gate)
        {
            _code = fixedCode ?? RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
            _codeExpires = DateTimeOffset.UtcNow + (lifetime ?? CodeLifetime);
            _codeAttempts = 0;
            return _code;
        }
    }

    public (string Code, DateTimeOffset Expires)? ActiveCode
    {
        get { lock (_gate) return _code is not null && DateTimeOffset.UtcNow < _codeExpires ? (_code, _codeExpires) : null; }
    }

    public void CancelPairing() { lock (_gate) _code = null; }

    /// <summary>Returns a new token if the code is right; null otherwise.</summary>
    public string? TryCompletePairing(string code, string deviceName, out string? error)
    {
        PairedDevice device;
        string token;
        lock (_gate)
        {
            if (_code is null || DateTimeOffset.UtcNow >= _codeExpires)
            {
                error = "No pairing code is active. On the PC, choose “Pair new device…” from the FluentDeck tray icon.";
                return null;
            }
            if (++_codeAttempts > MaxAttemptsPerCode)
            {
                _code = null;
                error = "Too many attempts. Start pairing again on the PC.";
                return null;
            }
            if (!CryptographicOperations.FixedTimeEquals(System.Text.Encoding.UTF8.GetBytes(code.Trim()), System.Text.Encoding.UTF8.GetBytes(_code)))
            {
                error = "That code doesn’t match. Check the code on the PC and try again.";
                return null;
            }

            _code = null;
            token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            device = new PairedDevice(Clean(deviceName), Hash(token), DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
            _devices.Add(device);
            Save();
        }
        error = null;
        DevicePaired?.Invoke(device);
        return token;
    }

    public bool Validate(string? token, out PairedDevice? device)
    {
        device = null;
        if (string.IsNullOrEmpty(token)) return false;
        var hash = Hash(token);
        lock (_gate)
        {
            var i = _devices.FindIndex(d => CryptographicOperations.FixedTimeEquals(Convert.FromHexString(d.TokenHash), Convert.FromHexString(hash)));
            if (i < 0) return false;
            device = _devices[i] = _devices[i] with { LastSeen = DateTimeOffset.UtcNow };
            return true;
        }
    }

    public void Revoke(PairedDevice device)
    {
        lock (_gate)
        {
            _devices.RemoveAll(d => d.TokenHash == device.TokenHash);
            Save();
        }
    }

    private static string Hash(string token) => Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token)));
    private static string Clean(string name) => string.IsNullOrWhiteSpace(name) ? "Device" : name.Trim()[..Math.Min(name.Trim().Length, 60)];

    private List<PairedDevice> Load()
    {
        try
        {
            if (File.Exists(_paths.AuthFile))
                return JsonSerializer.Deserialize<List<PairedDevice>>(File.ReadAllText(_paths.AuthFile)) ?? [];
        }
        catch { }
        return [];
    }

    private void Save() => File.WriteAllText(_paths.AuthFile, JsonSerializer.Serialize(_devices, new JsonSerializerOptions { WriteIndented = true }));
}
