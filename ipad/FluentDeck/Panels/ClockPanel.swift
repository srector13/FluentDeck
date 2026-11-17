import SwiftUI

/// A client-only widget (no host topic) — also the simplest example of a panel.
struct ClockPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "clock",
        title: "Clock",
        summary: "The time and date in large rounded numerals. Runs on the iPad, so it works offline.",
        symbol: "clock",
        sizes: [.small, .medium, .large],
        defaultSize: .medium,
        view: { AnyView(ClockPanel(ctx: $0)) })

    @Environment(\.theme) private var theme

    private static let uses12Hour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    /// "1:24" or "13:24": no leading zero on a 12-hour clock.
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = ClockPanel.uses12Hour ? "h:mm" : "HH:mm"
        return formatter
    }()
    private static let period: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            GeometryReader { g in
                // Rounded numerals in the manner of the Lock Screen, anchored bottom-left.
                let size = max(34, min(g.size.height * 0.62, g.size.width * 0.3))
                VStack(alignment: .leading, spacing: size * 0.04) {
                    HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
                        Text(Self.time.string(from: date))
                            .font(.system(size: size, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                        if Self.uses12Hour {
                            Text(Self.period.string(from: date))
                                .font(.system(size: max(13, size * 0.16)))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(size: max(13, size * 0.12)))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .bottomLeading)
            }
        }
    }
}
