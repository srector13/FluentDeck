using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace FluentDeck.Core.Panels;

/// <summary>What the iPad learns about a host panel in the welcome message.</summary>
public sealed record PanelDescriptor(string Id, string Title, string Icon, int Version, IReadOnlyList<string> Actions);

/// <summary>
/// A host-side panel: owns one topic of state and a set of actions.
/// To add a new panel: subclass <see cref="PanelProvider"/>, then register it with
/// <c>services.AddPanel&lt;MyPanel&gt;()</c>. The iPad sees it in the welcome message automatically.
/// </summary>
public interface IPanelProvider
{
    PanelDescriptor Descriptor { get; }

    /// <summary>Latest state, pre-serialized as JSON (or null before the first publish).</summary>
    string? SnapshotJson { get; }

    /// <summary>Raised after <see cref="SnapshotJson"/> changes.</summary>
    event Action<IPanelProvider>? Changed;

    Task StartAsync(CancellationToken ct);
    Task StopAsync();

    /// <summary>Run an action. Return a JSON-serializable result or null. Throw <see cref="PanelActionException"/> for user-facing errors.</summary>
    Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct);
}

public sealed class PanelActionException(string message) : Exception(message);

public static class FluentJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        WriteIndented = false,
    };
}

/// <summary>Convenience base class: call <see cref="Publish{T}"/> whenever your state changes.
/// Identical consecutive states are dropped, so polling providers can publish blindly.</summary>
public abstract class PanelProvider : IPanelProvider
{
    private string? _snapshot;

    public abstract PanelDescriptor Descriptor { get; }
    public string? SnapshotJson => Volatile.Read(ref _snapshot);
    public event Action<IPanelProvider>? Changed;

    public virtual Task StartAsync(CancellationToken ct) => Task.CompletedTask;
    public virtual Task StopAsync() => Task.CompletedTask;
    public abstract Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct);

    protected void Publish<T>(T state)
    {
        var json = JsonSerializer.Serialize(state, FluentJson.Options);
        var previous = Interlocked.Exchange(ref _snapshot, json);
        if (previous != json) Changed?.Invoke(this);
    }

    protected static PanelActionException UnknownAction(string action) => new($"Unknown action '{action}'");
}

/// <summary>Typed readers for invoke args.</summary>
public static class Args
{
    public static double Double(this JsonObject args, string name)
        => args[name] is JsonValue v && v.TryGetValue<double>(out var d) ? d
           : throw new PanelActionException($"Missing number argument '{name}'");

    public static double Double(this JsonObject args, string name, double fallback)
        => args[name] is JsonValue v && v.TryGetValue<double>(out var d) ? d : fallback;

    public static string String(this JsonObject args, string name)
        => args[name] is JsonValue v && v.TryGetValue<string>(out var s) && s.Length > 0 ? s
           : throw new PanelActionException($"Missing string argument '{name}'");

    public static string? OptionalString(this JsonObject args, string name)
        => args[name] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public static bool Bool(this JsonObject args, string name, bool fallback = false)
        => args[name] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : fallback;

    public static float Volume(this JsonObject args, string name = "volume")
        => (float)Math.Clamp(args.Double(name), 0, 1);
}
