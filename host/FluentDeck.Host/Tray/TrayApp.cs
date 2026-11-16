using System.Diagnostics;
using System.Drawing.Drawing2D;
using FluentDeck.Core.Deck;
using FluentDeck.Core.Hosting;
using FluentDeck.Host.Interop;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Win32;

namespace FluentDeck.Host.Tray;

/// <summary>The only UI on the PC: a tray icon with pairing, device management and shortcuts.</summary>
internal sealed class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _icon;
    private readonly AuthStore _auth;
    private readonly Hub _hub;
    private readonly HostPaths _paths;
    private readonly HostSettings _settings;
    private readonly DeckPanel _deck;
    private readonly SynchronizationContext _ui;
    private PairingForm? _pairing;

    public TrayApp(IServiceProvider services)
    {
        _auth = services.GetRequiredService<AuthStore>();
        _hub = services.GetRequiredService<Hub>();
        _paths = services.GetRequiredService<HostPaths>();
        _settings = services.GetRequiredService<HostSettings>();
        _deck = services.GetRequiredService<DeckPanel>();
        _ui = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        var menu = new ContextMenuStrip { ShowImageMargin = false, RenderMode = ToolStripRenderMode.System };
        menu.Opening += (_, _) => BuildMenu(menu);

        _icon = new NotifyIcon
        {
            Icon = TrayIconFactory.Create(),
            Visible = true,
            ContextMenuStrip = menu,
        };
        _icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowPairing(); };
        UpdateTooltip();

        _hub.ClientsChanged += () => _ui.Post(_ => UpdateTooltip(), null);
        _auth.DevicePaired += device => _ui.Post(_ =>
        {
            _pairing?.Close();
            _icon.ShowBalloonTip(4000, "FluentDeck", $"{device.Name} is paired with this PC.", ToolTipIcon.Info);
        }, null);

        // First run: nothing paired yet, so go straight to pairing.
        if (_auth.Devices.Count == 0) _ui.Post(_ => ShowPairing(), null);
    }

    private void UpdateTooltip()
    {
        var n = _hub.ConnectedClientNames.Count;
        var text = n switch { 0 => "FluentDeck — no devices connected", 1 => $"FluentDeck — {_hub.ConnectedClientNames[0]} connected", _ => $"FluentDeck — {n} devices connected" };
        _icon.Text = text.Length > 63 ? text[..63] : text; // NotifyIcon limit
    }

    private void BuildMenu(ContextMenuStrip menu)
    {
        menu.Items.Clear();
        menu.Items.Add(new ToolStripMenuItem($"FluentDeck on {_settings.Name}") { Enabled = false });
        var ips = BonjourAdvertiser.LanAddresses();
        menu.Items.Add(new ToolStripMenuItem($"{(ips.Count > 0 ? ips[0].ToString() : "localhost")}:{_settings.Port}") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Pair new device…", null, (_, _) => ShowPairing());

        var devices = new ToolStripMenuItem("Paired devices");
        var paired = _auth.Devices;
        var connected = _hub.ConnectedClientNames;
        if (paired.Count == 0) devices.DropDownItems.Add(new ToolStripMenuItem("None yet") { Enabled = false });
        foreach (var d in paired)
        {
            var label = connected.Contains(d.Name) ? $"{d.Name}  •  connected" : $"{d.Name}  •  last seen {Ago(d.LastSeen)}";
            var item = new ToolStripMenuItem(label);
            item.DropDownItems.Add("Remove this device", null, (_, _) =>
            {
                if (MessageBox.Show($"Remove {d.Name}? It will need to pair again.", "FluentDeck", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) == DialogResult.OK)
                    _auth.Revoke(d);
            });
            devices.DropDownItems.Add(item);
        }
        menu.Items.Add(devices);
        menu.Items.Add(new ToolStripSeparator());
        var editing = new ToolStripMenuItem("Allow editing keys from the iPad") { Checked = _settings.AllowDeckEditing, CheckOnClick = true };
        editing.CheckedChanged += (_, _) => SetDeckEditing(editing.Checked);
        menu.Items.Add(editing);
        menu.Items.Add("Edit deck buttons (deck.json)", null, (_, _) => Open(_paths.DeckFile));
        menu.Items.Add("Open data folder", null, (_, _) => Open(_paths.Root));
        menu.Items.Add("Allow through Windows Firewall…", null, (_, _) => AllowFirewall());
        var startup = new ToolStripMenuItem("Start with Windows") { Checked = Startup.IsEnabled, CheckOnClick = true };
        startup.CheckedChanged += (_, _) => Startup.Set(startup.Checked);
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit FluentDeck", null, (_, _) => ExitThread());
    }

    private void ShowPairing()
    {
        if (_pairing is { IsDisposed: false }) { _pairing.Activate(); return; }
        _pairing = new PairingForm(_auth, _settings);
        _pairing.FormClosed += (_, _) => _pairing = null;
        _pairing.Show();
        _pairing.Activate();
    }

    /// <summary>With this on, a paired device can define what keys launch, so ask before enabling it.</summary>
    private void SetDeckEditing(bool allow)
    {
        if (allow && MessageBox.Show(
                "Paired devices will be able to add and change keys, including which programs they launch.\n\nOnly turn this on if you trust every paired device.",
                "FluentDeck", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
        _settings.AllowDeckEditing = allow;
        _settings.Save(_paths);
        _deck.SettingsChanged();
    }

    private void AllowFirewall()
    {
        var exe = Environment.ProcessPath ?? "";
        var args = $"advfirewall firewall add rule name=\"FluentDeck\" dir=in action=allow protocol=TCP localport={_settings.Port} profile=private program=\"{exe}\"";
        try { Process.Start(new ProcessStartInfo("netsh", args) { Verb = "runas", UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden }); }
        catch { /* user declined the UAC prompt */ }
    }

    private static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch { Process.Start(new ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true }); }
    }

    private static string Ago(DateTimeOffset? t)
    {
        if (t is null) return "never";
        var d = DateTimeOffset.UtcNow - t.Value;
        return d.TotalMinutes < 2 ? "just now" : d.TotalHours < 1 ? $"{(int)d.TotalMinutes} min ago" : d.TotalDays < 1 ? $"{(int)d.TotalHours} h ago" : $"{(int)d.TotalDays} d ago";
    }

    protected override void ExitThreadCore()
    {
        _icon.Visible = false;
        _icon.Dispose();
        base.ExitThreadCore();
    }
}

internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "FluentDeck";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string;
        }
    }

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled) key.SetValue(Name, $"\"{Environment.ProcessPath}\"");
        else key.DeleteValue(Name, throwOnMissingValue: false);
    }
}

/// <summary>Draws the tray icon (an accent tile with a 3×2 grid of deck keys) so there's no .ico asset to ship.</summary>
internal static class TrayIconFactory
{
    public static Icon Create()
    {
        var size = SystemInformation.SmallIconSize.Width * 2; // crisp at 200% scaling
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            var accent = Color.FromArgb(0x00, 0x78, 0xD4);
            using (var path = RoundedRect(new RectangleF(1, 1, size - 2, size - 2), size * 0.22f))
            using (var brush = new SolidBrush(accent))
                g.FillPath(brush, path);

            const int cols = 3, rows = 2;
            var gap = size * 0.07f;
            var cell = (size * 0.74f - (cols - 1) * gap) / cols;
            var left = (size - (cols * cell + (cols - 1) * gap)) / 2;
            var top = (size - (rows * cell + (rows - 1) * gap)) / 2;
            using var lit = new SolidBrush(Color.White);
            using var dim = new SolidBrush(Color.FromArgb(180, Color.White));
            for (var r = 0; r < rows; r++)
                for (var c = 0; c < cols; c++)
                {
                    using var p = RoundedRect(new RectangleF(left + c * (cell + gap), top + r * (cell + gap), cell, cell), cell * 0.25f);
                    g.FillPath(r == 0 && c == 0 ? lit : dim, p);
                }
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
