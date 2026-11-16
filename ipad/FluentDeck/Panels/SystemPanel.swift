import SwiftUI

/// CPU, memory and battery for the PC, plus lock / sleep / screen-off.
struct SystemPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "system",
        title: "System",
        summary: "Live CPU, memory and battery for your PC, with lock, sleep and screen-off.",
        symbol: "cpu",
        requires: "system",
        sizes: [.small, .medium, .large],
        defaultSize: .medium,
        view: { AnyView(SystemPanel(ctx: $0)) })

    @Environment(\.fluent) private var theme

    var body: some View {
        if let s = ctx.state("system", as: SystemState.self) {
            switch ctx.size {
            case .small: small(s)
            case .large, .wide: large(s)
            default: medium(s)
            }
        } else {
            PanelEmptyState(symbol: "cpu", text: "System info unavailable")
        }
    }

    private func small(_ s: SystemState) -> some View {
        VStack(spacing: 8) {
            FluentRingGauge(value: s.cpu / 100, label: "CPU").frame(width: 92, height: 92)
            Text("Memory \(Int(s.memory))%").font(FluentFont.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ s: SystemState) -> some View {
        HStack(spacing: 18) {
            FluentRingGauge(value: s.cpu / 100, label: "CPU").frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 10) {
                Stat(title: "Memory", detail: String(format: "%.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb), value: s.memory / 100)
                if let b = s.battery {
                    Stat(title: b.charging ? "Battery · charging" : "Battery", detail: "\(b.percent)%", value: Double(b.percent) / 100,
                         tint: b.percent <= 15 && !b.charging ? theme.critical : nil)
                } else {
                    Text("Up \(Self.uptime(s.uptimeSeconds))").font(FluentFont.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ s: SystemState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.hostName).font(FluentFont.bodyStrong).lineLimit(1)
                    Text("Up \(Self.uptime(s.uptimeSeconds))").font(FluentFont.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .foregroundStyle(theme.textPrimary)
            Stat(title: "CPU", detail: "\(Int(s.cpu))%", value: s.cpu / 100)
            Stat(title: "Memory", detail: String(format: "%.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb), value: s.memory / 100)
            if let b = s.battery {
                Stat(title: b.charging ? "Battery · charging" : "Battery", detail: "\(b.percent)%", value: Double(b.percent) / 100,
                     tint: b.percent <= 15 && !b.charging ? theme.critical : nil)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                action("Lock", "lock", "lock")
                action("Sleep", "moon", "sleep")
                action("Screen off", "display", "displayOff")
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ name: String) -> some View {
        Button { ctx.run("system", name) } label: {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
        }
        .buttonStyle(FluentButtonStyle(kind: .standard, fill: true))
    }

    static func uptime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s / 3600) % 24, m = (s / 60) % 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private struct Stat: View {
    let title: String
    let detail: String
    let value: Double
    var tint: Color? = nil
    @Environment(\.fluent) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(theme.textPrimary)
                Spacer()
                Text(detail).foregroundStyle(theme.textSecondary).monospacedDigit()
            }
            .font(FluentFont.caption)
            FluentProgressBar(value: value, tint: tint)
        }
    }
}
