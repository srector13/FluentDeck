using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using FluentDeck.Core.Hosting;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Host.Interop;

/// <summary>
/// Advertises _fluentdeck._tcp over mDNS using Windows' built-in DNS-SD API (dnsapi.dll, Windows 10 1809+),
/// so the iPad finds the PC without typing an IP. TXT record: id, ip (comma list), port, proto.
/// Re-registers when the network changes.
/// </summary>
public sealed class BonjourAdvertiser : IDisposable
{
    public const string ServiceType = "_fluentdeck._tcp";

    private readonly HostSettings _settings;
    private readonly ILogger<BonjourAdvertiser> _log;
    private readonly object _gate = new();
    private IntPtr _instance, _request, _ip4;
    private readonly RegisterComplete _callback;
    private bool _started;

    public BonjourAdvertiser(HostSettings settings, ILogger<BonjourAdvertiser> log)
    {
        _settings = settings; _log = log;
        _callback = OnComplete; // keep the delegate alive for the native side
    }

    public void Start()
    {
        _started = true;
        Register();
        NetworkChange.NetworkAddressChanged += OnNetworkChanged;
    }

    private void OnNetworkChanged(object? sender, EventArgs e)
    {
        // Debounce: DHCP renewals fire several events.
        Task.Delay(1500).ContinueWith(_ => { if (_started) { Unregister(); Register(); } });
    }

    private void Register()
    {
        lock (_gate)
        {
            try
            {
                var ips = LanAddresses();
                var instanceName = Sanitize(_settings.Name);
                var serviceName = $"{instanceName}.{ServiceType}.local";
                var hostName = $"{Environment.MachineName}.local";

                if (ips.Count > 0)
                {
                    _ip4 = Marshal.AllocHGlobal(4);
                    Marshal.Copy(ips[0].GetAddressBytes(), 0, _ip4, 4); // network byte order, as IP4_ADDRESS expects
                }

                string[] keys = ["id", "ip", "port", "proto"];
                string[] values = [_settings.HostId, string.Join(",", ips), _settings.Port.ToString(), "1"];

                _instance = DnsServiceConstructInstance(serviceName, hostName, _ip4, IntPtr.Zero,
                    (ushort)_settings.Port, 0, 0, (uint)keys.Length, keys, values);
                if (_instance == IntPtr.Zero) throw new InvalidOperationException("DnsServiceConstructInstance failed");

                var request = new DNS_SERVICE_REGISTER_REQUEST
                {
                    Version = DNS_QUERY_REQUEST_VERSION1,
                    InterfaceIndex = 0,
                    pServiceInstance = _instance,
                    pRegisterCompletionCallback = Marshal.GetFunctionPointerForDelegate(_callback),
                    pQueryContext = IntPtr.Zero,
                    hCredentials = IntPtr.Zero,
                    unicastEnabled = 0,
                };
                _request = Marshal.AllocHGlobal(Marshal.SizeOf<DNS_SERVICE_REGISTER_REQUEST>());
                Marshal.StructureToPtr(request, _request, false);

                var status = DnsServiceRegister(_request, IntPtr.Zero);
                if (status != DNS_REQUEST_PENDING)
                    _log.LogWarning("Bonjour registration failed to start (status {Status}); the iPad can still connect by IP", status);
                else
                    _log.LogInformation("Advertising {Service} on {Ips}", serviceName, string.Join(", ", ips));
            }
            catch (Exception ex)
            {
                _log.LogWarning(ex, "Bonjour advertising unavailable; the iPad can still connect by IP");
                FreeNative();
            }
        }
    }

    private void Unregister()
    {
        lock (_gate)
        {
            if (_request != IntPtr.Zero)
            {
                try { DnsServiceDeRegister(_request, IntPtr.Zero); } catch { }
            }
            FreeNative();
        }
    }

    private void FreeNative()
    {
        // Registration and deregistration complete asynchronously and the docs don't say when Windows
        // stops reading these blocks, so they're deliberately not freed (a few hundred bytes per
        // network change, reclaimed at exit) — safer than a use-after-free in dnsapi.
        _request = IntPtr.Zero;
        _instance = IntPtr.Zero;
        _ip4 = IntPtr.Zero;
    }

    private void OnComplete(uint status, IntPtr context, IntPtr instance)
    {
        if (status != 0) _log.LogWarning("Bonjour registration completed with status {Status}", status);
    }

    public void Dispose()
    {
        if (!_started) return;
        _started = false;
        NetworkChange.NetworkAddressChanged -= OnNetworkChanged;
        Unregister();
    }

    /// <summary>Private IPv4 addresses of interfaces that are up, Wi-Fi/Ethernet first.</summary>
    public static List<IPAddress> LanAddresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                        n.NetworkInterfaceType is not (NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) &&
                        !n.Description.Contains("Virtual", StringComparison.OrdinalIgnoreCase) &&
                        !n.Description.Contains("Hyper-V", StringComparison.OrdinalIgnoreCase))
            .OrderBy(n => n.NetworkInterfaceType is NetworkInterfaceType.Wireless80211 or NetworkInterfaceType.Ethernet ? 0 : 1)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Select(a => a.Address)
            .Where(a => a.AddressFamily == AddressFamily.InterNetwork && IsPrivate(a))
            .Distinct()
            .ToList();

    private static bool IsPrivate(IPAddress a)
    {
        var b = a.GetAddressBytes();
        return b[0] == 10 || (b[0] == 172 && b[1] is >= 16 and <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] is >= 64 and <= 127);
    }

    private static string Sanitize(string name)
    {
        var s = new string(name.Select(c => char.IsLetterOrDigit(c) || c is '-' or ' ' or '(' or ')' ? c : '-').ToArray()).Trim();
        return s.Length == 0 ? "FluentDeck" : s[..Math.Min(s.Length, 60)];
    }

    // ── dnsapi.dll ──
    private const uint DNS_QUERY_REQUEST_VERSION1 = 1;
    private const uint DNS_REQUEST_PENDING = 9506;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void RegisterComplete(uint status, IntPtr queryContext, IntPtr instance);

    [StructLayout(LayoutKind.Sequential)]
    private struct DNS_SERVICE_REGISTER_REQUEST
    {
        public uint Version;
        public uint InterfaceIndex;
        public IntPtr pServiceInstance;
        public IntPtr pRegisterCompletionCallback;
        public IntPtr pQueryContext;
        public IntPtr hCredentials;
        public int unicastEnabled;
    }

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern IntPtr DnsServiceConstructInstance(
        string pServiceName, string pHostName, IntPtr pIp4, IntPtr pIp6,
        ushort wPort, ushort wPriority, ushort wWeight, uint dwPropertiesCount,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr)] string[] keys,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr)] string[] values);

    [DllImport("dnsapi.dll", ExactSpelling = true)] private static extern uint DnsServiceRegister(IntPtr pRequest, IntPtr pCancel);
    [DllImport("dnsapi.dll", ExactSpelling = true)] private static extern uint DnsServiceDeRegister(IntPtr pRequest, IntPtr pCancel);
}
