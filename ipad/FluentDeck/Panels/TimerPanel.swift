import AudioToolbox
import SwiftUI
import UIKit

/// A countdown on the iPad, with a Pomodoro mode that follows each focus session with a short
/// break. Its state lives in the widget's settings, so it keeps counting across launches.
struct TimerPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "timer",
        title: "Timer",
        summary: "A countdown with quick lengths, and a Pomodoro mode: 25 minutes of focus, then a 5-minute break. Runs on the iPad.",
        symbol: "timer",
        sizes: [.small, .medium, .large],
        defaultSize: .large,
        defaultConfig: ["minutes": "25"],
        menu: { ctx in TimerPanel.menu(ctx) },
        view: { AnyView(TimerPanel(ctx: $0)) })

    static let presets = [5, 10, 15, 25, 45, 60]
    static let breakMinutes = 5

    static func menu(_ ctx: PanelContext) -> [ActionItem] {
        let timer = TimerModel(ctx)
        var items: [ActionItem] = [.header("Length")]
        items += presets.map { m in
            ActionItem.action("\(m) minutes", checked: timer.minutes == m) { timer.setMinutes(m) }
        }
        items.append(.separator)
        items.append(.action("Pomodoro: focus, then a \(breakMinutes)-minute break", checked: timer.pomodoro) { timer.setPomodoro(!timer.pomodoro) })
        return items
    }

    @Environment(\.theme) private var theme

    var body: some View {
        let timer = TimerModel(ctx)
        TimelineView(.periodic(from: .now, by: timer.running ? 0.5 : 3600)) { context in
            let left = timer.remaining(at: context.date)
            let progress = timer.length > 0 ? left / timer.length : 0
            Group {
                switch ctx.size {
                case .small: small(timer, left: left, progress: progress)
                case .medium: medium(timer, left: left, progress: progress)
                default: large(timer, left: left, progress: progress)
                }
            }
        }
        .task(id: timer.endsAt) {
            guard let end = timer.endsAt else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled, TimerModel(ctx).endsAt == end else { return }
            // Ring only if it ended just now, not while the app was closed long ago.
            TimerModel(ctx).finish(alert: end.timeIntervalSinceNow > -60)
        }
    }

    private func small(_ t: TimerModel, left: Double, progress: Double) -> some View {
        Button { t.toggle() } label: {
            ZStack {
                Ring(progress: progress, lineWidth: 7, tint: t.tint(theme))
                Text(TimerModel.clock(left)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).padding(12)
            }
            .padding(4)
        }
        .buttonStyle(DimOnPress())
        .accessibilityLabel(t.running ? "Pause" : "Start")
    }

    private func medium(_ t: TimerModel, left: Double, progress: Double) -> some View {
        HStack(spacing: 18) {
            Ring(progress: progress, lineWidth: 8, tint: t.tint(theme))
                .overlay { Image(systemName: t.onBreak ? "cup.and.saucer.fill" : "timer").font(.system(size: 20)).foregroundStyle(theme.textSecondary) }
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8) {
                Text(t.phaseTitle).font(AppFont.caption.weight(.semibold)).foregroundStyle(t.tint(theme))
                Text(TimerModel.clock(left))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                controls(t)
            }
            Spacer(minLength: 0)
        }
    }

    private func large(_ t: TimerModel, left: Double, progress: Double) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Ring(progress: progress, lineWidth: 10, tint: t.tint(theme))
                VStack(spacing: 4) {
                    Text(t.phaseTitle).font(AppFont.caption.weight(.semibold)).foregroundStyle(t.tint(theme))
                    Text(TimerModel.clock(left))
                        .font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                }
                .padding(28)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                ForEach([5, 15, 25, 45], id: \.self) { m in
                    Button("\(m)") { t.setMinutes(m) }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.minutes == m ? Color.black : theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(t.minutes == m ? Color.white : theme.controlFill))
                        .buttonStyle(DimOnPress())
                        .accessibilityLabel("\(m) minutes")
                }
            }
            controls(t)
        }
    }

    private func controls(_ t: TimerModel) -> some View {
        HStack(spacing: 12) {
            Button { t.reset() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44).background(Circle().fill(theme.controlFill))
            }
            .foregroundStyle(theme.textPrimary)
            .buttonStyle(DimOnPress())
            .accessibilityLabel("Reset")
            Button { t.toggle() } label: {
                Image(systemName: t.running ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52).background(Circle().fill(.white))
            }
            .buttonStyle(DimOnPress())
            .accessibilityLabel(t.running ? "Pause" : "Start")
        }
    }
}

/// The timer's state, read from and written to the widget's settings.
@MainActor
struct TimerModel {
    let ctx: PanelContext
    init(_ ctx: PanelContext) { self.ctx = ctx }

    var minutes: Int { Int(ctx.config["minutes"] ?? "") ?? 25 }
    var pomodoro: Bool { ctx.config["mode"] == "pomodoro" }
    var onBreak: Bool { pomodoro && ctx.config["phase"] == "break" }
    var endsAt: Date? { ctx.config["end"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) }
    var running: Bool { endsAt != nil }
    var length: Double { Double(onBreak ? TimerPanel.breakMinutes : minutes) * 60 }

    var phaseTitle: String {
        if onBreak { return "BREAK" }
        if pomodoro { return "FOCUS" }
        return running ? "TIMER" : (ctx.config["left"] == nil ? "\(minutes) MIN" : "PAUSED")
    }

    func tint(_ theme: Theme) -> Color { onBreak ? theme.success : theme.accent }

    func remaining(at date: Date) -> Double {
        if let end = endsAt { return max(0, end.timeIntervalSince(date)) }
        return ctx.config["left"].flatMap(Double.init) ?? length
    }

    func toggle() { running ? pause() : start() }

    func start() {
        let left = remaining(at: .now)
        set("end", String(Date.now.addingTimeInterval(left > 0 ? left : length).timeIntervalSince1970))
        set("left", nil)
    }

    func pause() {
        set("left", String(remaining(at: .now)))
        set("end", nil)
    }

    func reset() {
        set("end", nil)
        set("left", nil)
        set("phase", nil)
    }

    func setMinutes(_ m: Int) {
        set("minutes", String(m))
        reset()
    }

    func setPomodoro(_ on: Bool) {
        set("mode", on ? "pomodoro" : nil)
        if on { set("minutes", "25") }
        reset()
    }

    /// Time's up: chime, and in Pomodoro mode start the break (or wait for the next focus session).
    func finish(alert: Bool) {
        if alert {
            AudioServicesPlaySystemSound(1005)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let wasBreak = onBreak
        reset()
        if pomodoro && !wasBreak {
            set("phase", "break")
            set("end", String(Date.now.addingTimeInterval(Double(TimerPanel.breakMinutes) * 60).timeIntervalSince1970))
        }
    }

    private func set(_ key: String, _ value: String?) { ctx.updateConfig(key, value) }

    /// "24:59", or "1:02:03" past an hour.
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A progress ring that runs clockwise from the top.
private struct Ring: View {
    let progress: Double
    var lineWidth: CGFloat
    var tint: Color
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle().stroke(theme.trackFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
        }
        .padding(lineWidth / 2)
    }
}
