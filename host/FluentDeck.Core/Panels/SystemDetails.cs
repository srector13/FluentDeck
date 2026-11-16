using System.ComponentModel;
using System.Diagnostics;

namespace FluentDeck.Core.Panels;

public sealed record DiskInfo(string Name, double FreeGb, double TotalGb);

/// <param name="Cpu">Percent of the whole machine, summed over the processes with this name.</param>
public sealed record ProcessInfo(string Name, double Cpu, double MemoryMb);

public sealed record SystemDetailsState(IReadOnlyList<DiskInfo> Disks, IReadOnlyList<ProcessInfo> Processes);

/// <summary>Disks and the busiest processes, sampled only when a device asks (the system panel's
/// "details" action), so nothing is measured while nobody is looking. CPU share is the processor
/// time used since the previous call; the first call has nothing to compare with and reports 0.</summary>
public sealed class SystemDetails
{
    private const double GB = 1024d * 1024 * 1024;
    private readonly object _gate = new();
    private Dictionary<int, TimeSpan> _lastCpu = new();
    private DateTime _lastAt;
    private SystemDetailsState? _last;

    public SystemDetailsState Sample(int top = 6)
    {
        lock (_gate)
        {
            var now = DateTime.UtcNow;
            // Several devices polling at once share one measurement.
            if (_last is not null && (now - _lastAt).TotalMilliseconds < 900) return _last;
            var elapsed = _lastAt == default ? 0 : (now - _lastAt).TotalSeconds;

            var cpuNow = new Dictionary<int, TimeSpan>();
            var byName = new Dictionary<string, (double Cpu, long Memory)>(StringComparer.OrdinalIgnoreCase);
            foreach (var process in Process.GetProcesses())
            {
                using (process)
                {
                    try
                    {
                        var name = process.ProcessName;
                        if (string.IsNullOrEmpty(name) || name is "Idle" or "System Idle Process") continue;
                        var memory = process.WorkingSet64;
                        double share = 0;
                        try
                        {
                            var used = process.TotalProcessorTime;
                            cpuNow[process.Id] = used;
                            if (elapsed > 0 && _lastCpu.TryGetValue(process.Id, out var before) && used >= before)
                                share = (used - before).TotalSeconds / (elapsed * Environment.ProcessorCount) * 100;
                        }
                        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or NotSupportedException)
                        {
                            // A protected process: its memory is readable, its processor time isn't.
                        }
                        var sum = byName.GetValueOrDefault(name);
                        byName[name] = (sum.Cpu + share, sum.Memory + memory);
                    }
                    catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or NotSupportedException)
                    {
                        // It exited while we were looking.
                    }
                }
            }

            var processes = byName
                .OrderByDescending(p => Math.Round(p.Value.Cpu, 1))
                .ThenByDescending(p => p.Value.Memory)
                .Take(top)
                .Select(p => new ProcessInfo(p.Key, Math.Round(Math.Clamp(p.Value.Cpu, 0, 100), 1), Math.Round(p.Value.Memory / (1024d * 1024), 0)))
                .ToList();

            _lastCpu = cpuNow;
            _lastAt = now;
            return _last = new SystemDetailsState(Disks(), processes);
        }
    }

    private static List<DiskInfo> Disks()
    {
        var disks = new List<DiskInfo>();
        var seen = new HashSet<(long, long)>();
        try
        {
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    // Fixed drives of a real size; the same volume mounted twice counts once.
                    if (!drive.IsReady || drive.DriveType != DriveType.Fixed || drive.TotalSize < 8 * GB) continue;
                    if (!seen.Add((drive.TotalSize, drive.AvailableFreeSpace))) continue;
                    var name = drive.Name.TrimEnd('\\');
                    disks.Add(new DiskInfo(name.Length == 0 ? drive.Name : name, Math.Round(drive.AvailableFreeSpace / GB, 1), Math.Round(drive.TotalSize / GB, 1)));
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* skip that drive */ }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* no drive list */ }
        return disks.Take(4).ToList();
    }
}
