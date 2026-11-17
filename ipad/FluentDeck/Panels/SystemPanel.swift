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
        drawer: { AnyView(SystemDrawer(ctx: $0)) },
        drawerSizes: [.small, .medium],
        view: { AnyView(SystemPanel(ctx: $0)) })

    @Environment(\.theme) private var theme

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
            RingGauge(value: s.cpu / 100, label: "CPU").frame(width: 92, height: 92)
            Text("Memory \(Int(s.memory))%").font(AppFont.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ s: SystemState) -> some View {
        HStack(spacing: 18) {
            RingGauge(value: s.cpu / 100, label: "CPU").frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 10) {
                Stat(title: "Memory", detail: String(format: "%.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb), value: s.memory / 100)
                if let b = s.battery {
                    Stat(title: b.charging ? "Battery · charging" : "Battery", detail: "\(b.percent)%", value: Double(b.percent) / 100,
                         tint: b.percent <= 15 && !b.charging ? theme.critical : nil)
                } else {
                    Text("Up \(Self.uptime(s.uptimeSeconds))").font(AppFont.caption).foregroundStyle(theme.textSecondary)
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
                    Text(s.hostName).font(AppFont.bodyStrong).lineLimit(1)
                    Text("Up \(Self.uptime(s.uptimeSeconds))").font(AppFont.caption).foregroundStyle(theme.textSecondary)
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
        .buttonStyle(PillButtonStyle(kind: .standard, fill: true))
    }

    static func uptime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let d = s / 86400, h = (s / 3600) % 24, m = (s / 60) % 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// The compact system widget's drawer: load and disks on the left, the busiest apps on the right,
/// and the power actions underneath. Disks and apps are measured by the PC while this is open.
struct SystemDrawer: View {
    let ctx: PanelContext
    @Environment(\.theme) private var theme
    @State private var details: SystemDetailsState?

    private var hostHasDetails: Bool {
        ctx.connection.panels.first { $0.id == "system" }?.actions.contains("details") ?? false
    }

    var body: some View {
        if let s = ctx.state("system", as: SystemState.self) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 36) {
                    load(s).frame(maxWidth: .infinity, alignment: .topLeading)
                    busiest.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                HStack(spacing: 8) {
                    action("Lock", "lock", "lock")
                    action("Sleep", "moon", "sleep")
                    action("Screen off", "display", "displayOff")
                }
            }
            .task { await poll() }
        } else {
            PanelEmptyState(symbol: "cpu", text: "System info unavailable").frame(height: 120)
        }
    }

    private func load(_ s: SystemState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(s.hostName) · up \(SystemPanel.uptime(Double(s.uptimeSeconds)))")
                .font(AppFont.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Stat(title: "CPU", detail: "\(Int(s.cpu))%", value: s.cpu / 100)
            Stat(title: "Memory", detail: String(format: "%.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb), value: s.memory / 100)
            if let b = s.battery {
                Stat(title: b.charging ? "Battery · charging" : "Battery", detail: "\(b.percent)%", value: Double(b.percent) / 100,
                     tint: b.percent <= 15 && !b.charging ? theme.critical : nil)
            }
            ForEach(details?.disks ?? []) { disk in
                Stat(title: "Disk \(disk.name)", detail: String(format: "%.0f GB free of %.0f", disk.freeGb, disk.totalGb),
                     value: disk.totalGb > 0 ? 1 - disk.freeGb / disk.totalGb : 0)
            }
        }
    }

    @ViewBuilder
    private var busiest: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Busiest apps")
                .font(AppFont.caption)
                .foregroundStyle(theme.textSecondary)
            if let details {
                ForEach(details.processes) { process in
                    HStack(spacing: 10) {
                        Text(process.name).foregroundStyle(theme.textPrimary).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(String(format: "%.0f%%", process.cpu)).foregroundStyle(theme.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                        Text(Self.memory(process.memoryMb)).foregroundStyle(theme.textSecondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .font(AppFont.caption)
                    .monospacedDigit()
                }
            } else if hostHasDetails {
                Spinner(size: 18).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Text("Update FluentDeck on the PC to see its busiest apps and disks here.")
                    .font(AppFont.caption)
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ name: String) -> some View {
        Button { ctx.run("system", name) } label: {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle(kind: .standard, fill: true))
    }

    /// Ask the PC every two seconds while the drawer is open.
    private func poll() async {
        guard hostHasDetails else { return }
        while !Task.isCancelled {
            if let result = try? await ctx.connection.invoke("system", "details"),
               let fresh = try? result.decode(SystemDetailsState.self) {
                details = fresh
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    static func memory(_ megabytes: Double) -> String {
        megabytes >= 1024 ? String(format: "%.1f GB", megabytes / 1024) : String(format: "%.0f MB", megabytes)
    }
}

private struct Stat: View {
    let title: String
    let detail: String
    let value: Double
    var tint: Color? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(theme.textPrimary)
                Spacer()
                Text(detail).foregroundStyle(theme.textSecondary).monospacedDigit()
            }
            .font(AppFont.caption)
            LevelBar(value: value, tint: tint)
        }
    }
}
