import SwiftUI

/// How the AI server on the network is doing: up or down, the model it serves, how fast it's
/// generating, what's queued, how full its cache is, and (with a GPU exporter) the GPU itself.
struct SparkPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "spark",
        title: "Spark",
        summary: "Health of your AI server: online, the model it serves, tokens per second, requests and cache, and the GPU if an exporter runs. Reads vLLM straight from the iPad; set the address in Settings.",
        symbol: "cpu.fill",
        sizes: [.small, .medium, .large, .wide],
        defaultSize: .medium,
        drawer: { AnyView(SparkDetail(ctx: $0)) },
        drawerSizes: [.small, .medium],
        view: { AnyView(SparkPanel(ctx: $0)) })

    @Environment(\.theme) private var theme
    @Environment(AppModel.self) private var app
    @State private var monitor = SparkMonitor.shared

    var body: some View {
        Group {
            if let s = monitor.snapshot {
                switch ctx.size {
                case .small: small(s)
                case .medium: medium(s)
                default: SparkDetail(ctx: ctx, embedded: true)
                }
            } else if app.settings.sparkAddress.isEmpty && LaunchOptions.spark == nil {
                VStack(spacing: 10) {
                    PanelEmptyState(symbol: "cpu", text: "Add your AI server's address").frame(maxHeight: 60)
                    Button("Open Settings") { app.showSettings() }.buttonStyle(PillButtonStyle(kind: .accent, compact: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await monitor.watch() }
    }

    private func small(_ s: SparkSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SparkStatus(snapshot: s)
            Spacer(minLength: 0)
            SparkRate(value: s.generationRate, online: s.online, size: 30)
            Text("tokens/s").font(AppFont.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ s: SparkSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SparkStatus(snapshot: s)
                Text(s.model ?? (s.online ? "—" : s.error ?? "Offline"))
                    .font(AppFont.caption).foregroundStyle(theme.textSecondary).lineLimit(2)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SparkRate(value: s.generationRate, online: s.online, size: 34)
                    Text("tok/s").font(AppFont.caption).foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                SparkFigure(label: "Running", value: s.online ? "\(Int(s.running))" : "—")
                SparkFigure(label: "Queued", value: s.online ? "\(Int(s.waiting))" : "—", warn: s.waiting > 0)
                SparkFigure(label: "Cache", value: s.kvCache.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            }
        }
    }
}

/// Everything at once: the large widget, and the drawer of the small ones.
struct SparkDetail: View {
    let ctx: PanelContext
    var embedded = false
    @Environment(\.theme) private var theme
    @State private var monitor = SparkMonitor.shared

    var body: some View {
        Group {
            if let s = monitor.snapshot {
                content(s)
            } else {
                PanelEmptyState(symbol: "cpu", text: "No AI server set up").frame(height: 120)
            }
        }
        .task { if !embedded { await monitor.watch() } }
    }

    private func content(_ s: SparkSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SparkStatus(snapshot: s)
                Spacer()
                if let model = s.model {
                    Text(model).font(AppFont.caption.weight(.semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
            }
            if let error = s.error, !s.online {
                Text(error).font(AppFont.caption).foregroundStyle(theme.caution)
            }
            HStack(spacing: 0) {
                SparkStat(label: "Generating", value: s.online ? Self.rate(s.generationRate) : "—", unit: "tok/s")
                SparkStat(label: "Reading", value: s.online ? Self.rate(s.promptRate) : "—", unit: "tok/s")
                SparkStat(label: "First token", value: s.timeToFirstToken.map { Self.seconds($0) } ?? "—", unit: "")
                SparkStat(label: "Requests", value: s.online ? "\(Int(s.running))" : "—", unit: s.waiting > 0 ? "+\(Int(s.waiting)) queued" : "running")
            }
            SparkGraph(values: s.history)
                .frame(minHeight: 44, maxHeight: embedded ? .infinity : 90)
            if let kv = s.kvCache {
                Meter(label: "KV cache", detail: "\(Int((kv * 100).rounded()))%\(s.contextLength.map { " · \(Self.context($0)) context" } ?? "")", value: kv)
            }
            if let gpu = s.gpu {
                gpuBlock(gpu)
            }
        }
    }

    private func gpuBlock(_ gpu: SparkSnapshot.GPU) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let util = gpu.utilization {
                Meter(label: "GPU", detail: "\(Int(util.rounded()))%", value: util / 100)
            }
            if let used = gpu.memoryUsedGB, let total = gpu.memoryTotalGB, total > 0 {
                Meter(label: "GPU memory", detail: String(format: "%.0f of %.0f GB", used, total), value: used / total)
            }
            HStack(spacing: 16) {
                if let t = gpu.temperature {
                    Label("\(Int(t.rounded()))°C", systemImage: "thermometer.medium")
                        .foregroundStyle(t >= 85 ? theme.critical : t >= 75 ? theme.caution : theme.textSecondary)
                }
                if let w = gpu.power {
                    Label("\(Int(w.rounded())) W", systemImage: "bolt.fill").foregroundStyle(theme.textSecondary)
                }
            }
            .font(AppFont.caption)
        }
    }

    static func rate(_ v: Double) -> String { v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v) }
    static func seconds(_ v: Double) -> String { v < 1 ? "\(Int((v * 1000).rounded())) ms" : String(format: "%.1f s", v) }
    static func context(_ n: Int) -> String { n >= 1024 ? "\(n / 1024)K" : "\(n)" }
}

private struct SparkStatus: View {
    let snapshot: SparkSnapshot
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(color: !snapshot.online ? theme.critical : snapshot.waiting > 0 ? theme.caution : theme.success)
            Text("Spark").font(AppFont.bodyStrong).foregroundStyle(theme.textPrimary)
            Text(state).font(AppFont.caption).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var state: String {
        if !snapshot.online {
            if let seen = snapshot.lastSeen { return "Offline · seen \(seen.formatted(date: .omitted, time: .shortened))" }
            return "Offline"
        }
        return snapshot.running > 0 ? "Busy" : "Idle"
    }
}

private struct SparkRate: View {
    let value: Double
    let online: Bool
    var size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Text(online ? SparkDetail.rate(value) : "—")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.textPrimary)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.3), value: value)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}

private struct SparkFigure: View {
    let label: String
    let value: String
    var warn = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(AppFont.caption).foregroundStyle(theme.textSecondary)
            Text(value).font(AppFont.bodyStrong).monospacedDigit().foregroundStyle(warn ? theme.caution : theme.textPrimary)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}

private struct SparkStat: View {
    let label: String
    let value: String
    let unit: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(AppFont.caption).foregroundStyle(theme.textSecondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.system(size: 11)).foregroundStyle(theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Meter: View {
    let label: String
    let detail: String
    let value: Double
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(AppFont.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                Spacer()
                Text(detail).font(AppFont.caption).foregroundStyle(theme.textSecondary)
            }
            LevelBar(value: value, tint: value > 0.9 ? theme.critical : value > 0.75 ? theme.caution : theme.accent)
        }
    }
}

/// Tokens per second over the last few minutes.
private struct SparkGraph: View {
    let values: [Double]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { g in
            let peak = max(10, values.max() ?? 10)
            let step = g.size.width / 59
            let start = g.size.width - step * CGFloat(max(values.count - 1, 0))
            let points = values.enumerated().map { i, v in
                CGPoint(x: start + CGFloat(i) * step, y: g.size.height - 2 - CGFloat(v / peak) * (g.size.height - 4))
            }
            ZStack {
                if let first = points.first, let last = points.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: g.size.height))
                        for point in points { p.addLine(to: point) }
                        p.addLine(to: CGPoint(x: last.x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [theme.accent.opacity(0.4), theme.accent.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: first)
                        for point in points.dropFirst() { p.addLine(to: point) }
                    }
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
