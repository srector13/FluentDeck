using FluentDeck.Core.Deck;
using FluentDeck.Core.Hosting;
using FluentDeck.Core.Panels;
using FluentDeck.DevHost;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

// Dev host: same protocol and deck as the real Windows host, with simulated panels.
//   FLUENTDECK_HOME       override the data folder (default: <LocalAppData>/FluentDeck-Dev)
//   FLUENTDECK_PAIR_CODE  use a fixed pairing code that stays valid after each pair (handy for UI tests)
//   FLUENTDECK_NAME       the PC name shown on the iPad

var home = Environment.GetEnvironmentVariable("FLUENTDECK_HOME")
           ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FluentDeck-Dev");
var paths = new HostPaths(home);
var settings = HostSettings.Load(paths);
settings.DisplayName = Environment.GetEnvironmentVariable("FLUENTDECK_NAME") is { Length: > 0 } name
    ? name
    : settings.DisplayName ?? $"{Environment.MachineName} (DevHost)";

var builder = FluentDeckServer.CreateBuilder(args, paths, settings);
builder.Services.AddSingleton<IDeckActionExecutor, LoggingDeckExecutor>();
builder.Services.AddPanel<SimMediaPanel>();
builder.Services.AddPanel<SimAudioPanel>();
builder.Services.AddPanel<SimSystemPanel>();
builder.Services.AddPanel<SimThemePanel>();

var app = builder.Build();
app.MapFluentDeck();
await app.Services.StartFluentDeckAsync();

var auth = app.Services.GetRequiredService<AuthStore>();
var fixedCode = Environment.GetEnvironmentVariable("FLUENTDECK_PAIR_CODE");
auth.ReusableCode = !string.IsNullOrEmpty(fixedCode);
var code = auth.BeginPairing(TimeSpan.FromHours(12), fixedCode);

Console.WriteLine($"""

    FluentDeck DevHost "{settings.Name}"
      ws://<this-machine-ip>:{settings.Port}/ws
      data folder: {paths.Root}  (edit deck.json there — it hot-reloads)
      pairing code: {code}   (valid 12 h)

    """);

await app.RunAsync();
