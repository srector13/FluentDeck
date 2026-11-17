using FluentDeck.Core.Deck;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using FluentDeck.Host.Panels;
using FluentDeck.Host.Tray;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Host;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        using var mutex = new Mutex(true, @"Local\FluentDeck.Host", out var firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("FluentDeck is already running — look for its icon in the system tray.", "FluentDeck",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }

        if (args.Contains("--console")) Native.AllocConsole();
        args = args.Where(a => a != "--console").ToArray();

        ApplicationConfiguration.Initialize();

        var paths = new HostPaths();
        var settings = HostSettings.Load(paths);

        var builder = FluentDeckServer.CreateBuilder(args, paths, settings);
        builder.Logging.AddProvider(new FileLoggerProvider(Path.Combine(paths.Root, "host.log")));

        // ── Panels. To add one: write a PanelProvider and register it here. ──
        builder.Services.AddSingleton<IDeckActionExecutor, WindowsDeckExecutor>();
        builder.Services.AddPanel<MediaPanel>();
        builder.Services.AddPanel<AudioPanel>();
        builder.Services.AddPanel<SystemPanel>();
        builder.Services.AddPanel<ThemePanel>();
        builder.Services.AddPanel<DesktopsPanel>();
        builder.Services.AddSingleton<BonjourAdvertiser>();

        var app = builder.Build();
        app.MapFluentDeck();
        var log = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("FluentDeck");

        try
        {
            // Start the server and panels on the thread pool (MTA) so COM/WinRT objects live there,
            // not on the UI thread.
            Task.Run(async () =>
            {
                await app.StartAsync();
                await app.Services.StartFluentDeckAsync();
            }).GetAwaiter().GetResult();
        }
        catch (Exception ex) when (ex is IOException || ex.InnerException is IOException)
        {
            log.LogError(ex, "Could not listen on port {Port}", settings.Port);
            MessageBox.Show($"FluentDeck couldn't listen on port {settings.Port} — is something else using it?\n\n" +
                            $"Change \"port\" in {paths.SettingsFile} and start FluentDeck again.",
                            "FluentDeck", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        var bonjour = app.Services.GetRequiredService<BonjourAdvertiser>();
        if (settings.AdvertiseBonjour) bonjour.Start();

        log.LogInformation("FluentDeck {Version} listening on port {Port} as {Name}", HostSettings.Version, settings.Port, settings.Name);

        Application.Run(new TrayApp(app.Services));

        bonjour.Dispose();
        Task.Run(async () =>
        {
            await app.Services.StopFluentDeckAsync();
            await app.StopWithinAsync(TimeSpan.FromSeconds(3));
        }).Wait(TimeSpan.FromSeconds(5));
        return 0;
    }

    private static async Task StopWithinAsync(this WebApplication app, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        await app.StopAsync(cts.Token);
    }
}
