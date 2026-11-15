using Microsoft.Extensions.Logging;

namespace FluentDeck.Host.Interop;

/// <summary>Minimal file logger so a tray app without a console still leaves a trail (host.log, capped at 2 MB).</summary>
internal sealed class FileLoggerProvider : ILoggerProvider
{
    private readonly string _path;
    private readonly object _gate = new();
    private const long MaxBytes = 2 * 1024 * 1024;

    public FileLoggerProvider(string path)
    {
        _path = path;
        try { if (File.Exists(path) && new FileInfo(path).Length > MaxBytes) File.Delete(path); } catch { }
    }

    public ILogger CreateLogger(string categoryName) => new FileLogger(this, categoryName);
    public void Dispose() { }

    private void Write(string line)
    {
        lock (_gate)
        {
            try { File.AppendAllText(_path, line + Environment.NewLine); } catch { }
        }
    }

    private sealed class FileLogger(FileLoggerProvider owner, string category) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;
            if (category.StartsWith("Microsoft.", StringComparison.Ordinal) && logLevel < LogLevel.Warning) return;
            var shortCategory = category[(category.LastIndexOf('.') + 1)..];
            var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {logLevel.ToString()[..4].ToUpperInvariant()} {shortCategory}: {formatter(state, exception)}";
            if (exception is not null) line += Environment.NewLine + exception;
            owner.Write(line);
        }
    }
}
