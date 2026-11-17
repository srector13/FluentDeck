using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json.Nodes;

namespace FluentDeck.Core.Panels;

/// <summary>Download and upload speed of the main network connection, sampled every second, and
/// disk space every half minute. .NET reads both on any OS, so the Windows host and the DevHost
/// share this panel and the DevHost reports its own machine's real traffic.</summary>
public sealed class NetworkPanel : PanelProvider, IDisposable
{
    private const int HistoryLength = 60;
    private readonly Queue<double> _down = new(), _up = new();
    private Timer? _timer;
    private string? _adapterId;
    private long _lastRx, _lastTx;
    private DateTime _lastAt;
    private List<DiskInfo> _disks = [];
    private DateTime _disksAt = DateTime.MinValue;

    public override PanelDescriptor Descriptor => BuiltInPanels.Network;

    public override Task StartAsync(CancellationToken ct)
    {
        Sample();
        _timer = new Timer(_ => Sample(), null, 1000, 1000);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }
    public void Dispose() { _timer?.Dispose(); _timer = null; }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct) => throw UnknownAction(action);

    /// <summary>The connection that carries the most traffic among those that are up and have a
    /// gateway (so not loopback, VPN-less virtual switches or idle adapters).</summary>
    private static NetworkInterface? Primary()
    {
        try
        {
            var up = NetworkInterface.GetAllNetworkInterfaces()
                .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
                .ToList();
            var routed = up.Where(n => { try { return n.GetIPProperties().GatewayAddresses.Count > 0; } catch { return false; } }).ToList();
            return (routed.Count > 0 ? routed : up).OrderByDescending(Total).FirstOrDefault();
        }
        catch (NetworkInformationException) { return null; }
    }

    private static long Total(NetworkInterface n)
    {
        try { var s = n.GetIPStatistics(); return s.BytesReceived + s.BytesSent; } catch { return 0; }
    }

    private void Sample()
    {
        lock (_down)
        {
            var nic = Primary();
            double down = 0, up = 0;
            string? address = null;
            if (nic is not null)
            {
                long rx = 0, tx = 0;
                try { var s = nic.GetIPStatistics(); rx = s.BytesReceived; tx = s.BytesSent; } catch { /* keep zeros */ }
                var now = DateTime.UtcNow;
                if (nic.Id == _adapterId && _lastAt != default)
                {
                    var seconds = Math.Max(0.2, (now - _lastAt).TotalSeconds);
                    down = Math.Max(0, (rx - _lastRx) / seconds);
                    up = Math.Max(0, (tx - _lastTx) / seconds);
                }
                _adapterId = nic.Id; _lastRx = rx; _lastTx = tx; _lastAt = now;
                try
                {
                    address = nic.GetIPProperties().UnicastAddresses
                        .FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork)?.Address.ToString();
                }
                catch { /* no address */ }
            }

            Push(_down, down);
            Push(_up, up);
            if (DateTime.UtcNow - _disksAt > TimeSpan.FromSeconds(30))
            {
                _disks = SystemDetails.Disks();
                _disksAt = DateTime.UtcNow;
            }
            Publish(new NetworkState(nic?.Name, address, Math.Round(down), Math.Round(up),
                _down.Select(v => Math.Round(v)).ToList(), _up.Select(v => Math.Round(v)).ToList(), _disks));
        }
    }

    private static void Push(Queue<double> history, double value)
    {
        history.Enqueue(value);
        while (history.Count > HistoryLength) history.Dequeue();
    }
}
