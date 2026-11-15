using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Core.Panels;

/// <summary>All panels known to this host, keyed by topic id.</summary>
public sealed class PanelRegistry
{
    private readonly Dictionary<string, IPanelProvider> _panels;
    private readonly ILogger<PanelRegistry> _log;

    public PanelRegistry(IEnumerable<IPanelProvider> panels, ILogger<PanelRegistry> log)
    {
        _log = log;
        _panels = new(StringComparer.OrdinalIgnoreCase);
        foreach (var p in panels)
        {
            if (!_panels.TryAdd(p.Descriptor.Id, p))
                throw new InvalidOperationException($"Two panels registered with id '{p.Descriptor.Id}'");
        }
    }

    public IReadOnlyCollection<IPanelProvider> All => _panels.Values;
    public IReadOnlyList<PanelDescriptor> Descriptors => _panels.Values.Select(p => p.Descriptor).ToList();
    public IPanelProvider? Find(string id) => _panels.GetValueOrDefault(id);

    public async Task StartAllAsync(CancellationToken ct)
    {
        foreach (var p in _panels.Values)
        {
            try { await p.StartAsync(ct); }
            catch (Exception ex) { _log.LogError(ex, "Panel {Panel} failed to start", p.Descriptor.Id); }
        }
    }

    public async Task StopAllAsync()
    {
        foreach (var p in _panels.Values)
        {
            try { await p.StopAsync(); } catch (Exception ex) { _log.LogWarning(ex, "Panel {Panel} failed to stop", p.Descriptor.Id); }
        }
    }

    public Task<object?> InvokeAsync(string panel, string action, JsonObject? args, CancellationToken ct)
    {
        var provider = Find(panel) ?? throw new PanelActionException($"Unknown panel '{panel}'");
        return provider.InvokeAsync(action, args ?? new JsonObject(), ct);
    }
}

public static class PanelServiceExtensions
{
    /// <summary>Register a panel. It is created once and started with the host.</summary>
    public static IServiceCollection AddPanel<T>(this IServiceCollection services) where T : class, IPanelProvider
    {
        services.AddSingleton<T>();
        services.AddSingleton<IPanelProvider>(sp => sp.GetRequiredService<T>());
        return services;
    }
}
