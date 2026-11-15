using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using FluentDeck.Core.Panels;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace FluentDeck.Core.Hosting;

/// <summary>Accepts WebSocket clients, authenticates them, and fans panel state out to subscribers.</summary>
public sealed class Hub
{
    public const int ProtocolVersion = 1;

    private readonly PanelRegistry _registry;
    private readonly AuthStore _auth;
    private readonly HostSettings _settings;
    private readonly ILogger<Hub> _log;
    private readonly ConcurrentDictionary<Guid, ClientSession> _clients = new();
    private readonly ConcurrentDictionary<string, byte> _dirty = new(StringComparer.OrdinalIgnoreCase);
    private int _flushScheduled;

    /// <summary>Coalescing window: at most ~30 state frames per topic per second.</summary>
    private static readonly TimeSpan FlushDelay = TimeSpan.FromMilliseconds(33);

    public Hub(PanelRegistry registry, AuthStore auth, HostSettings settings, ILogger<Hub> log)
    {
        _registry = registry; _auth = auth; _settings = settings; _log = log;
        foreach (var p in registry.All) p.Changed += provider => MarkDirty(provider.Descriptor.Id);
    }

    public event Action? ClientsChanged;
    public IReadOnlyList<string> ConnectedClientNames => _clients.Values.Where(c => c.IsAuthenticated).Select(c => c.ClientName).ToList();

    public async Task HandleAsync(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("FluentDeck: connect with a WebSocket.");
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        var session = new ClientSession(this, socket, context.Connection.RemoteIpAddress?.ToString() ?? "?");
        _clients[session.Id] = session;
        _log.LogInformation("Client connected from {Remote}", session.Remote);
        try
        {
            await session.RunAsync(context.RequestAborted);
        }
        catch (Exception ex) when (ex is OperationCanceledException or WebSocketException)
        {
            // normal disconnects
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Client {Remote} failed", session.Remote);
        }
        finally
        {
            _clients.TryRemove(session.Id, out _);
            _log.LogInformation("Client {Name} ({Remote}) disconnected", session.ClientName, session.Remote);
            ClientsChanged?.Invoke();
        }
    }

    private void MarkDirty(string topic)
    {
        _dirty[topic] = 1;
        if (Interlocked.CompareExchange(ref _flushScheduled, 1, 0) == 0) _ = FlushSoonAsync();
    }

    private async Task FlushSoonAsync()
    {
        await Task.Delay(FlushDelay);
        Volatile.Write(ref _flushScheduled, 0);
        foreach (var topic in _dirty.Keys.ToList())
        {
            _dirty.TryRemove(topic, out _);
            var frame = StateFrame(topic);
            if (frame is null) continue;
            foreach (var c in _clients.Values)
                if (c.IsSubscribed(topic)) c.Enqueue(frame);
        }
    }

    private string? StateFrame(string topic)
    {
        var p = _registry.Find(topic);
        var data = p?.SnapshotJson;
        if (p is null || data is null) return null;
        return $"{{\"type\":\"state\",\"topic\":{JsonSerializer.Serialize(p.Descriptor.Id)},\"data\":{data}}}";
    }

    // ───────────────────────────── per-client session ─────────────────────────────

    private sealed class ClientSession(Hub hub, WebSocket socket, string remote)
    {
        private readonly Channel<string> _outbox = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });
        private readonly HashSet<string> _subscriptions = new(StringComparer.OrdinalIgnoreCase);
        private int _backlog;
        private int _pairAttempts;
        private volatile bool _authenticated;

        private const int MaxMessageBytes = 256 * 1024;
        private const int MaxBacklog = 2000;
        private static readonly TimeSpan AuthTimeout = TimeSpan.FromMinutes(3);
        private static readonly TimeSpan InvokeTimeout = TimeSpan.FromSeconds(15);

        public Guid Id { get; } = Guid.NewGuid();
        public string Remote { get; } = remote;
        public string ClientName { get; private set; } = "unknown";
        public bool IsAuthenticated => _authenticated;

        public bool IsSubscribed(string topic)
        {
            if (!_authenticated) return false;
            lock (_subscriptions) return _subscriptions.Contains(topic);
        }

        public void Enqueue(string frame)
        {
            if (Interlocked.Increment(ref _backlog) > MaxBacklog)
            {
                hub._log.LogWarning("Client {Name} is not keeping up; disconnecting", ClientName);
                _outbox.Writer.TryComplete();
                return;
            }
            _outbox.Writer.TryWrite(frame);
        }

        private void Send(JsonObject message) => Enqueue(message.ToJsonString());

        public async Task RunAsync(CancellationToken aborted)
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(aborted);
            var writer = WriteLoopAsync(cts.Token);

            Send(new JsonObject
            {
                ["type"] = "server",
                ["protocol"] = ProtocolVersion,
                ["hostId"] = hub._settings.HostId,
                ["name"] = hub._settings.Name,
                ["version"] = HostSettings.Version,
            });

            // Unauthenticated sockets get a few minutes to pair, then they're dropped.
            _ = Task.Delay(AuthTimeout, cts.Token).ContinueWith(t =>
            {
                if (!t.IsCanceled && !_authenticated) cts.Cancel();
            }, TaskScheduler.Default);

            try
            {
                await ReadLoopAsync(cts.Token);
            }
            finally
            {
                _outbox.Writer.TryComplete();
                cts.Cancel();
                try { await writer; } catch { }
            }
        }

        private async Task WriteLoopAsync(CancellationToken ct)
        {
            await foreach (var frame in _outbox.Reader.ReadAllAsync(ct))
            {
                Interlocked.Decrement(ref _backlog);
                if (socket.State != WebSocketState.Open) break;
                await socket.SendAsync(Encoding.UTF8.GetBytes(frame), WebSocketMessageType.Text, true, ct);
            }
            if (socket.State == WebSocketState.Open)
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
        }

        private async Task ReadLoopAsync(CancellationToken ct)
        {
            var buffer = new byte[16 * 1024];
            using var message = new MemoryStream();
            while (socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                message.SetLength(0);
                WebSocketReceiveResult result;
                do
                {
                    result = await socket.ReceiveAsync(buffer, ct);
                    if (result.MessageType == WebSocketMessageType.Close) return;
                    message.Write(buffer, 0, result.Count);
                    if (message.Length > MaxMessageBytes) throw new WebSocketException("Message too large");
                } while (!result.EndOfMessage);

                if (result.MessageType != WebSocketMessageType.Text) continue;

                JsonObject? msg = null;
                try { msg = JsonNode.Parse(message.ToArray()) as JsonObject; } catch (JsonException) { }
                if (msg is null)
                {
                    Send(new JsonObject { ["type"] = "error", ["message"] = "Malformed JSON" });
                    continue;
                }
                await HandleAsync(msg, ct);
            }
        }

        private Task HandleAsync(JsonObject msg, CancellationToken ct)
        {
            var type = msg["type"]?.GetValue<string>();
            if (type == "ping") { Send(new JsonObject { ["type"] = "pong" }); return Task.CompletedTask; }

            if (!_authenticated)
            {
                switch (type)
                {
                    case "hello": Hello(msg); break;
                    case "pair": Pair(msg); break;
                    default: Send(AuthError("Say hello first.", needsPairing: false)); break;
                }
                return Task.CompletedTask;
            }

            switch (type)
            {
                case "subscribe": Subscribe(msg["topics"] as JsonArray, add: true); break;
                case "unsubscribe": Subscribe(msg["topics"] as JsonArray, add: false); break;
                case "invoke": _ = InvokeAsync(msg, ct); break;
                case "hello": Welcome(); break;
                default: Send(new JsonObject { ["type"] = "error", ["message"] = $"Unknown message type '{type}'" }); break;
            }
            return Task.CompletedTask;
        }

        private void Hello(JsonObject msg)
        {
            ClientName = ClientNameFrom(msg);
            if (hub._auth.Validate(msg["token"]?.GetValue<string>(), out var device))
            {
                ClientName = device!.Name;
                Authenticated();
            }
            else
            {
                Send(AuthError("This device isn’t paired with this PC (or its pairing was removed).", needsPairing: true));
            }
        }

        private void Pair(JsonObject msg)
        {
            if (++_pairAttempts > 10) { Send(AuthError("Too many pairing attempts on this connection.", false)); return; }
            ClientName = ClientNameFrom(msg);
            var token = hub._auth.TryCompletePairing(msg["code"]?.GetValue<string>() ?? "", ClientName, out var error);
            if (token is null) { Send(AuthError(error ?? "Pairing failed.", needsPairing: true)); return; }
            Send(new JsonObject { ["type"] = "paired", ["token"] = token, ["hostId"] = hub._settings.HostId });
            Authenticated();
        }

        private void Authenticated()
        {
            _authenticated = true;
            hub._log.LogInformation("Client {Name} authenticated", ClientName);
            Welcome();
            hub.ClientsChanged?.Invoke();
        }

        private void Welcome()
        {
            var panels = JsonSerializer.SerializeToNode(hub._registry.Descriptors, FluentJson.Options);
            Send(new JsonObject
            {
                ["type"] = "welcome",
                ["hostId"] = hub._settings.HostId,
                ["name"] = hub._settings.Name,
                ["panels"] = panels,
            });
        }

        private void Subscribe(JsonArray? topics, bool add)
        {
            if (topics is null) return;
            var names = topics.Select(t => t?.GetValue<string>()).OfType<string>().ToList();
            lock (_subscriptions)
            {
                foreach (var t in names)
                    if (add) _subscriptions.Add(t); else _subscriptions.Remove(t);
            }
            if (!add) return;
            foreach (var t in names)
                if (hub.StateFrame(t) is { } frame) Enqueue(frame); // immediate snapshot
        }

        private async Task InvokeAsync(JsonObject msg, CancellationToken ct)
        {
            var id = msg["id"]?.GetValue<string>();
            var panel = msg["panel"]?.GetValue<string>() ?? "";
            var action = msg["action"]?.GetValue<string>() ?? "";
            var args = msg["args"] as JsonObject;

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(InvokeTimeout);
            JsonObject reply;
            try
            {
                var data = await hub._registry.InvokeAsync(panel, action, args?.DeepClone() as JsonObject, timeout.Token);
                reply = new JsonObject { ["type"] = "result", ["id"] = id, ["ok"] = true, ["data"] = data is null ? null : JsonSerializer.SerializeToNode(data, FluentJson.Options) };
            }
            catch (PanelActionException ex)
            {
                reply = new JsonObject { ["type"] = "result", ["id"] = id, ["ok"] = false, ["error"] = ex.Message };
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                reply = new JsonObject { ["type"] = "result", ["id"] = id, ["ok"] = false, ["error"] = "The PC took too long to respond." };
            }
            catch (Exception ex)
            {
                hub._log.LogWarning(ex, "{Panel}.{Action} failed", panel, action);
                reply = new JsonObject { ["type"] = "result", ["id"] = id, ["ok"] = false, ["error"] = ex.Message };
            }
            if (id is not null) Send(reply);
        }

        private static JsonObject AuthError(string reason, bool needsPairing) =>
            new() { ["type"] = "authError", ["reason"] = reason, ["needsPairing"] = needsPairing };

        private static string ClientNameFrom(JsonObject msg) =>
            msg["client"]?["name"]?.GetValue<string>() is { Length: > 0 } n ? n[..Math.Min(n.Length, 60)] : "Device";
    }
}
