using FluentDeck.Core.Hosting;
using FluentDeck.Host.Interop;

namespace FluentDeck.Host.Tray;

/// <summary>Shows the 6-digit pairing code with a countdown, in Windows 11 styling (Mica + dark title bar).</summary>
internal sealed class PairingForm : Form
{
    private readonly AuthStore _auth;
    private readonly Label _code;
    private readonly Label _countdown;
    private readonly System.Windows.Forms.Timer _timer;
    private DateTimeOffset _expires;

    public PairingForm(AuthStore auth, HostSettings settings)
    {
        _auth = auth;
        var dark = Native.AppsUseDarkTheme();
        var fg = dark ? Color.White : Color.FromArgb(0x1A, 0x1A, 0x1A);
        var secondary = dark ? Color.FromArgb(0xC5, 0xC5, 0xC5) : Color.FromArgb(0x5C, 0x5C, 0x5C);

        Text = "Pair a device — FluentDeck";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(440, 270);
        BackColor = dark ? Color.FromArgb(0x20, 0x20, 0x20) : Color.FromArgb(0xF3, 0xF3, 0xF3);
        Font = new Font("Segoe UI Variable Text", 10f);
        ShowInTaskbar = true;
        TopMost = true;
        Icon = TrayIconFactory.Create();

        var title = new Label
        {
            Text = "Enter this code on your iPad",
            Font = new Font("Segoe UI Variable Display", 15f, FontStyle.Bold),
            ForeColor = fg, AutoSize = false, TextAlign = ContentAlignment.MiddleLeft,
            Bounds = new Rectangle(28, 22, 384, 34),
        };
        var body = new Label
        {
            Text = $"Open FluentDeck on the iPad, choose “{settings.Name}”, and type the code below.",
            ForeColor = secondary, AutoSize = false,
            Bounds = new Rectangle(28, 58, 384, 44),
        };
        _code = new Label
        {
            Font = new Font("Segoe UI Variable Display", 40f, FontStyle.Bold),
            ForeColor = fg, AutoSize = false, TextAlign = ContentAlignment.MiddleCenter,
            Bounds = new Rectangle(28, 104, 384, 80),
        };
        _countdown = new Label
        {
            ForeColor = secondary, AutoSize = false, TextAlign = ContentAlignment.MiddleCenter,
            Bounds = new Rectangle(28, 184, 384, 24),
        };
        var newCode = new Button
        {
            Text = "New code", FlatStyle = FlatStyle.System,
            Bounds = new Rectangle(232, 222, 90, 32),
        };
        newCode.Click += (_, _) => Generate();
        var close = new Button
        {
            Text = "Close", FlatStyle = FlatStyle.System, DialogResult = DialogResult.Cancel,
            Bounds = new Rectangle(330, 222, 82, 32),
        };
        close.Click += (_, _) => Close();
        CancelButton = close;

        Controls.AddRange([title, body, _code, _countdown, newCode, close]);

        _timer = new System.Windows.Forms.Timer { Interval = 500 };
        _timer.Tick += (_, _) => Tick();
        Generate();
        _timer.Start();

        HandleCreated += (_, _) => Native.ApplyWindowsChrome(Handle, dark);
    }

    private void Generate()
    {
        var code = _auth.BeginPairing();
        _expires = DateTimeOffset.UtcNow + AuthStore.CodeLifetime;
        _code.Text = $"{code[..3]} {code[3..]}";
        Tick();
    }

    private void Tick()
    {
        var left = _expires - DateTimeOffset.UtcNow;
        if (left <= TimeSpan.Zero || _auth.ActiveCode is null)
        {
            _countdown.Text = "Code expired — choose New code.";
            _code.ForeColor = Color.Gray;
            return;
        }
        _code.ForeColor = Native.AppsUseDarkTheme() ? Color.White : Color.FromArgb(0x1A, 0x1A, 0x1A);
        _countdown.Text = $"Expires in {(int)left.TotalMinutes}:{left.Seconds:D2}";
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _timer.Stop();
        _timer.Dispose();
        base.OnFormClosed(e);
    }
}
