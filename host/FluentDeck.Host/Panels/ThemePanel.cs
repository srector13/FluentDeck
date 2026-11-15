using System.Text.Json.Nodes;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;
using Windows.UI.ViewManagement;
using WinColor = Windows.UI.Color;

namespace FluentDeck.Host.Panels;

/// <summary>Publishes the PC's light/dark mode and accent palette so the iPad matches Windows exactly.</summary>
internal sealed class ThemePanel : PanelProvider, IDisposable
{
    private UISettings? _ui;
    private System.Threading.Timer? _timer;

    public override PanelDescriptor Descriptor => BuiltInPanels.Theme;

    public override Task StartAsync(CancellationToken ct)
    {
        _ui = new UISettings();
        _ui.ColorValuesChanged += OnChanged;
        Emit();
        // The light/dark switch lives in the registry and doesn't always raise ColorValuesChanged.
        _timer = new System.Threading.Timer(_ => Emit(), null, 3000, 3000);
        return Task.CompletedTask;
    }

    private void OnChanged(UISettings sender, object args) => Emit();

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }

    public void Dispose()
    {
        _timer?.Dispose(); _timer = null;
        if (_ui is not null) { _ui.ColorValuesChanged -= OnChanged; _ui = null; }
    }

    private void Emit()
    {
        var ui = _ui;
        if (ui is null) return;
        try
        {
            Publish(new ThemeState(
                Native.AppsUseDarkTheme(),
                Hex(ui.GetColorValue(UIColorType.Accent)),
                Hex(ui.GetColorValue(UIColorType.AccentLight1)),
                Hex(ui.GetColorValue(UIColorType.AccentLight2)),
                Hex(ui.GetColorValue(UIColorType.AccentLight3)),
                Hex(ui.GetColorValue(UIColorType.AccentDark1)),
                Hex(ui.GetColorValue(UIColorType.AccentDark2)),
                Hex(ui.GetColorValue(UIColorType.AccentDark3))));
        }
        catch
        {
            Publish(ThemeState.Default with { IsDark = Native.AppsUseDarkTheme() });
        }
    }

    private static string Hex(WinColor c) => $"#{c.R:X2}{c.G:X2}{c.B:X2}";

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct) => throw UnknownAction(action);
}
