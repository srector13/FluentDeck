using FluentDeck.Core.Deck;
using FluentDeck.Core.Panels;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Core.Hosting;

/// <summary>Wires the shared server: Kestrel on the configured port, /ws, /assets, and the deck panel.
/// Hosts add their own panels and an <see cref="IDeckActionExecutor"/>.</summary>
public static class FluentDeckServer
{
    public static WebApplicationBuilder CreateBuilder(string[] args, HostPaths paths, HostSettings settings)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            Args = args,
            ContentRootPath = AppContext.BaseDirectory,
        });
        builder.WebHost.ConfigureKestrel(k => k.ListenAnyIP(settings.Port));
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);

        builder.Services
            .AddSingleton(paths)
            .AddSingleton(settings)
            .AddSingleton<AssetStore>()
            .AddSingleton<SystemDetails>()
            .AddSingleton<AuthStore>()
            .AddSingleton<PanelRegistry>()
            .AddSingleton<Hub>();
        builder.Services.AddPanel<DeckPanel>();
        return builder;
    }

    public static WebApplication MapFluentDeck(this WebApplication app)
    {
        app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(15) });

        app.Map("/ws", (HttpContext ctx, Hub hub) => hub.HandleAsync(ctx));

        app.MapGet("/assets/{key}", (string key, HttpContext ctx, AssetStore assets, AuthStore auth) =>
        {
            var header = ctx.Request.Headers.Authorization.ToString();
            var token = header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? header[7..] : null;
            if (!auth.Validate(token, out _)) return Results.Unauthorized();
            if (!assets.TryGet(key, out var data, out var type)) return Results.NotFound();
            ctx.Response.Headers.CacheControl = "private, max-age=86400, immutable";
            return Results.Bytes(data, type);
        });

        // Unauthenticated identity probe, handy for "is the host reachable?" checks.
        app.MapGet("/", (HostSettings s) => Results.Json(new { app = "FluentDeck", name = s.Name, hostId = s.HostId, protocol = Hub.ProtocolVersion }));
        return app;
    }

    /// <summary>Create the hub (so it observes every panel) and start all panels.</summary>
    public static async Task StartFluentDeckAsync(this IServiceProvider services, CancellationToken ct = default)
    {
        _ = services.GetRequiredService<Hub>();
        await services.GetRequiredService<PanelRegistry>().StartAllAsync(ct);
    }

    public static Task StopFluentDeckAsync(this IServiceProvider services)
        => services.GetRequiredService<PanelRegistry>().StopAllAsync();
}
