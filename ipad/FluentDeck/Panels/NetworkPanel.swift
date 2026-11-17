import SwiftUI

/// The PC's network speed, down and up, with the last minute drawn as a sparkline, and (in the
/// large size) how full its disks are.
struct NetworkPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "network",
        title: "Network & Disks",
        summary: "Download and upload speed of the PC's main connection, with the last minute as a graph, and free space on its disks.",
        symbol: "network",
        requires: "network",
        sizes: [.small, .medium, .large, .wide],
        defaultSize: .medium,
        view: { AnyView(NetworkPanel(ctx: $0)) })

    @Environment(\.theme) private var theme

    var body: some View {
        if let n = ctx.state("network", as: NetworkState.self) {
            switch ctx.size {
            case .small: small(n)
            case .large, .wide, .tall, .huge: large(n)
            default: medium(n)
            }
        } else {
            PanelEmptyState(symbol: "network", text: "Network info unavailable")
        }
    }

    private func small(_ n: NetworkState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Rate(symbol: "arrow.down", value: n.downBps, tint: theme.accent, compact: true)
            Rate(symbol: "arrow.up", value: n.upBps, tint: theme.success, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ n: NetworkState) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Rate(symbol: "arrow.down", value: n.downBps, tint: theme.accent)
                Rate(symbol: "arrow.up", value: n.upBps, tint: theme.success)
            }
            .frame(width: 150, alignment: .leading)
            Sparkline(down: n.downHistory, up: n.upHistory)
        }
    }

    private func large(_ n: NetworkState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "network").font(.system(size: 15))
                Text([n.adapter, n.address].compactMap { $0 }.joined(separator: " · "))
                    .font(AppFont.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.textSecondary)
            HStack(spacing: 22) {
                Rate(symbol: "arrow.down", value: n.downBps, tint: theme.accent)
                Rate(symbol: "arrow.up", value: n.upBps, tint: theme.success)
            }
            Sparkline(down: n.downHistory, up: n.upHistory)
                .frame(maxHeight: .infinity)
            if !n.disks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(n.disks.prefix(2)) { disk in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Disk \(disk.name)").font(AppFont.caption.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.0f GB free of %.0f", disk.freeGb, disk.totalGb)).font(AppFont.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .foregroundStyle(theme.textPrimary)
                            LevelBar(value: disk.totalGb > 0 ? 1 - disk.freeGb / disk.totalGb : 0,
                                     tint: disk.totalGb > 0 && disk.freeGb / disk.totalGb < 0.1 ? theme.critical : .white)
                        }
                    }
                }
            }
        }
    }

    /// "12.4 Mb/s", the way connection speeds are quoted (bits, not bytes).
    static func format(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let bits = bytesPerSecond * 8
        switch bits {
        case ..<1_000: return (String(format: "%.0f", bits), "b/s")
        case ..<1_000_000: return (String(format: bits < 100_000 ? "%.1f" : "%.0f", bits / 1_000), "Kb/s")
        case ..<1_000_000_000: return (String(format: bits < 100_000_000 ? "%.1f" : "%.0f", bits / 1_000_000), "Mb/s")
        default: return (String(format: "%.2f", bits / 1_000_000_000), "Gb/s")
        }
    }
}

private struct Rate: View {
    let symbol: String
    let value: Double
    let tint: Color
    var compact = false
    @Environment(\.theme) private var theme

    var body: some View {
        let f = NetworkPanel.format(value)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 13 : 15, weight: .bold))
                .foregroundStyle(tint)
            Text(f.value)
                .font(.system(size: compact ? 22 : 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
            Text(f.unit)
                .font(AppFont.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .animation(.easeOut(duration: 0.3), value: f.value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(symbol == "arrow.down" ? "Download" : "Upload") \(f.value) \(f.unit)")
    }
}

/// Download (filled) and upload (line) over the last minute, scaled together.
private struct Sparkline: View {
    let down: [Double]
    let up: [Double]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { g in
            let peak = max(1, (down + up).max() ?? 1)
            ZStack {
                area(down, peak: peak, in: g.size)
                    .fill(LinearGradient(colors: [theme.accent.opacity(0.45), theme.accent.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                line(down, peak: peak, in: g.size).stroke(theme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                line(up, peak: peak, in: g.size).stroke(theme.success, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .frame(minHeight: 40)
        .accessibilityHidden(true)
    }

    private func points(_ values: [Double], peak: Double, in size: CGSize) -> [CGPoint] {
        let samples = values.isEmpty ? [0] : values
        let step = size.width / CGFloat(max(59, samples.count - 1))
        let start = size.width - step * CGFloat(samples.count - 1)
        return samples.enumerated().map { i, v in
            CGPoint(x: start + CGFloat(i) * step, y: size.height - 2 - CGFloat(v / peak) * (size.height - 4))
        }
    }

    private func line(_ values: [Double], peak: Double, in size: CGSize) -> Path {
        Path { p in p.addLines(points(values, peak: peak, in: size)) }
    }

    private func area(_ values: [Double], peak: Double, in size: CGSize) -> Path {
        Path { p in
            let pts = points(values, peak: peak, in: size)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            p.addLines(pts)
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}
