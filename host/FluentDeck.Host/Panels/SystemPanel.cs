using System.Text.Json.Nodes;
using FluentDeck.Core.Panels;
using FluentDeck.Host.Interop;

namespace FluentDeck.Host.Panels;

/// <summary>CPU / memory / battery at 0.5 Hz, plus lock, sleep and screen-off.</summary>
internal sealed class SystemPanel : PanelProvider, IDisposable
{
    private System.Threading.Timer? _timer;
    private long _lastIdle, _lastTotal;

    public override PanelDescriptor Descriptor => BuiltInPanels.System;

    public override Task StartAsync(CancellationToken ct)
    {
        SampleCpu(); // prime the delta
        _timer = new System.Threading.Timer(_ => Emit(), null, 500, 2000);
        return Task.CompletedTask;
    }

    public override Task StopAsync() { Dispose(); return Task.CompletedTask; }
    public void Dispose() { _timer?.Dispose(); _timer = null; }

    private double SampleCpu()
    {
        if (!Native.GetSystemTimes(out var idle, out var kernel, out var user)) return 0;
        var total = kernel + user; // kernel time includes idle time
        var dIdle = idle - _lastIdle;
        var dTotal = total - _lastTotal;
        _lastIdle = idle; _lastTotal = total;
        return dTotal <= 0 ? 0 : Math.Clamp(100.0 * (dTotal - dIdle) / dTotal, 0, 100);
    }

    private void Emit()
    {
        var mem = new Native.MEMORYSTATUSEX { dwLength = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Native.MEMORYSTATUSEX>() };
        Native.GlobalMemoryStatusEx(ref mem);
        const double GB = 1024d * 1024 * 1024;
        var totalGb = mem.ullTotalPhys / GB;
        var usedGb = (mem.ullTotalPhys - mem.ullAvailPhys) / GB;

        BatteryState? battery = null;
        if (Native.GetSystemPowerStatus(out var power) && power.BatteryFlag != 128 && power.BatteryLifePercent <= 100)
            battery = new BatteryState(power.BatteryLifePercent, power.ACLineStatus == 1);

        Publish(new SystemState(
            Environment.MachineName,
            Math.Round(SampleCpu(), 1),
            (double)mem.dwMemoryLoad,
            Math.Round(usedGb, 1),
            Math.Round(totalGb, 1),
            battery,
            Environment.TickCount64 / 1000));
    }

    public override Task<object?> InvokeAsync(string action, JsonObject args, CancellationToken ct)
    {
        switch (action)
        {
            case "lock":
                if (!Native.LockWorkStation()) throw new PanelActionException("Windows refused to lock.");
                break;
            case "sleep":
                // Reply first, then sleep — otherwise the iPad never hears back.
                _ = Task.Delay(400).ContinueWith(_ => Native.SetSuspendState(false, false, false));
                break;
            case "displayOff":
                Native.PostMessage(Native.HWND_BROADCAST, Native.WM_SYSCOMMAND, Native.SC_MONITORPOWER, 2);
                break;
            default:
                throw UnknownAction(action);
        }
        return Task.FromResult<object?>(null);
    }
}
