using System.Globalization;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;

namespace FluentDeck.DevHost;

/// <summary>A stand-in for a vLLM server (and an NVIDIA DCGM exporter) so the iPad's Spark widget
/// can be developed and tested without the real box: /sim/vllm/health, /sim/vllm/v1/models,
/// /sim/vllm/metrics and /sim/dcgm/metrics, with counters that grow like a server under light use.</summary>
internal static class SimVllm
{
    private static readonly object Gate = new();
    private static readonly Random Rng = new(7);
    private static double _promptTokens = 182_000, _genTokens = 96_000, _ttftSum = 41.2, _e2eSum = 1_480, _requests = 512;
    private static DateTime _last = DateTime.UtcNow;
    private static int _running = 1;

    public static void Map(WebApplication app)
    {
        app.MapGet("/sim/vllm/health", () => Results.Ok());
        app.MapGet("/sim/vllm/v1/models", () => Results.Json(new
        {
            @object = "list",
            data = new[] { new { id = "qwen3.8-flash-next", @object = "model", owned_by = "vllm", max_model_len = 131072 } },
        }));
        app.MapGet("/sim/vllm/metrics", () => Results.Text(Metrics(), "text/plain; version=0.0.4"));
        app.MapGet("/sim/dcgm/metrics", () => Results.Text(Gpu(), "text/plain; version=0.0.4"));
    }

    private static string F(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);

    private static string Metrics()
    {
        lock (Gate)
        {
            var now = DateTime.UtcNow;
            var dt = Math.Clamp((now - _last).TotalSeconds, 0, 30);
            _last = now;
            _running = Math.Clamp(_running + Rng.Next(-1, 2), 0, 3);
            if (_running > 0)
            {
                _genTokens += dt * (38 + Rng.NextDouble() * 30) * _running;
                _promptTokens += dt * (120 + Rng.NextDouble() * 200);
                var finished = Rng.NextDouble() < 0.5 ? 1 : 0;
                _requests += finished;
                _ttftSum += finished * (0.18 + Rng.NextDouble() * 0.2);
                _e2eSum += finished * (2.5 + Rng.NextDouble() * 4);
            }
            const string m = "model_name=\"qwen3.8-flash-next\"";
            var s = new StringBuilder();
            s.AppendLine("# HELP vllm:num_requests_running Number of requests in model execution batches.");
            s.AppendLine("# TYPE vllm:num_requests_running gauge");
            s.AppendLine($"vllm:num_requests_running{{{m}}} {_running}");
            s.AppendLine($"vllm:num_requests_waiting{{{m}}} 0");
            s.AppendLine($"vllm:kv_cache_usage_perc{{{m}}} {F(0.08 + _running * 0.07 + Rng.NextDouble() * 0.03)}");
            s.AppendLine("# TYPE vllm:prompt_tokens_total counter");
            s.AppendLine($"vllm:prompt_tokens_total{{{m}}} {F(Math.Round(_promptTokens))}");
            s.AppendLine($"vllm:generation_tokens_total{{{m}}} {F(Math.Round(_genTokens))}");
            s.AppendLine($"vllm:request_success_total{{finished_reason=\"stop\",{m}}} {F(_requests)}");
            s.AppendLine($"vllm:time_to_first_token_seconds_sum{{{m}}} {F(_ttftSum)}");
            s.AppendLine($"vllm:time_to_first_token_seconds_count{{{m}}} {F(_requests)}");
            s.AppendLine($"vllm:e2e_request_latency_seconds_sum{{{m}}} {F(_e2eSum)}");
            s.AppendLine($"vllm:e2e_request_latency_seconds_count{{{m}}} {F(_requests)}");
            return s.ToString();
        }
    }

    private static string Gpu()
    {
        lock (Gate)
        {
            const string g = "gpu=\"0\",modelName=\"NVIDIA GB10\"";
            var busy = _running > 0;
            var s = new StringBuilder();
            s.AppendLine($"DCGM_FI_DEV_GPU_UTIL{{{g}}} {(busy ? 55 + Rng.Next(35) : Rng.Next(4))}");
            s.AppendLine($"DCGM_FI_DEV_GPU_TEMP{{{g}}} {(busy ? 61 + Rng.Next(8) : 44 + Rng.Next(4))}");
            s.AppendLine($"DCGM_FI_DEV_POWER_USAGE{{{g}}} {F(busy ? 88 + Rng.NextDouble() * 30 : 31 + Rng.NextDouble() * 6)}");
            s.AppendLine($"DCGM_FI_DEV_FB_USED{{{g}}} 98304");
            s.AppendLine($"DCGM_FI_DEV_FB_FREE{{{g}}} 24576");
            return s.ToString();
        }
    }
}
