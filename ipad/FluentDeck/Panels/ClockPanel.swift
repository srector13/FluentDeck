import SwiftUI

/// A client-only widget (no host topic) — also the simplest example of a panel.
struct ClockPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "clock",
        title: "Clock",
        summary: "The time and date, Windows lock-screen style. Runs on the iPad, so it works offline.",
        symbol: "clock",
        sizes: [.small, .medium, .large],
        defaultSize: .small,
        view: { AnyView(ClockPanel(ctx: $0)) })

    @Environment(\.fluent) private var theme

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            VStack(spacing: 2) {
                Text(date, format: .dateTime.hour().minute())
                    .font(ctx.size == .small ? FluentFont.titleLarge : FluentFont.display)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(date, format: ctx.size == .small ? .dateTime.weekday(.abbreviated).day() : .dateTime.weekday(.wide).month(.wide).day())
                    .font(ctx.size == .small ? FluentFont.caption : FluentFont.bodyLarge)
                    .foregroundStyle(theme.textSecondary)
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
