import SwiftUI

/// WinUI Slider: a faint rail, accent fill, and the signature thumb — a solid disc with an accent dot
/// that grows while you hold it. Drag anywhere on the track (44 pt tall touch area).
struct FluentSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var enabled = true
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.fluent) private var theme
    @State private var dragging = false

    private let thumb: CGFloat = 24
    private let track: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            let width = max(g.size.width - thumb, 1)
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let x = thumb / 2 + width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.controlStrongFill.opacity(0.32))
                    .frame(height: track)
                    .padding(.horizontal, thumb / 2)
                Capsule()
                    .fill(enabled ? theme.accent : theme.textDisabled)
                    .frame(width: max(x - thumb / 2, 0), height: track)
                    .padding(.leading, thumb / 2)
                ZStack {
                    Circle()
                        .fill(theme.controlSolidFill)
                        .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.12), radius: 2, y: 1)
                    Circle()
                        .fill(enabled ? theme.accent : theme.textDisabled)
                        .frame(width: dragging ? 14 : 11, height: dragging ? 14 : 11)
                }
                .frame(width: thumb, height: thumb)
                .offset(x: x - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let f = min(max((drag.location.x - thumb / 2) / width, 0), 1)
                        value = range.lowerBound + f * span
                    }
                    .onEnded { _ in
                        guard enabled else { return }
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.snappy(duration: 0.12), value: dragging)
        }
        .frame(height: Fluent.touchTarget)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(((value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne)) * 100)) percent"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }
}

/// Sends at most one update per interval while dragging, always delivering the last value.
@MainActor
final class Throttle {
    private let interval: TimeInterval
    private var last = Date.distantPast
    private var pending: (() -> Void)?
    private var scheduled = false

    init(interval: TimeInterval = 0.05) { self.interval = interval }

    func callAsFunction(_ work: @escaping () -> Void) {
        let now = Date()
        if now.timeIntervalSince(last) >= interval {
            last = now
            work()
            return
        }
        pending = work
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if let p = self.pending {
                self.pending = nil
                self.last = Date()
                p()
            }
        }
    }
}

/// A slider bound to a remote value: shows your finger's value while dragging (and briefly after,
/// until the PC catches up), and throttles updates to the host.
struct RemoteSlider: View {
    let remote: Double
    var range: ClosedRange<Double> = 0...1
    var enabled = true
    let send: (Double) -> Void
    var commit: ((Double) -> Void)? = nil

    @State private var local: Double?
    @State private var throttle = Throttle()
    @State private var releaseTask: Task<Void, Never>?

    var body: some View {
        FluentSlider(
            value: Binding(
                get: { local ?? remote },
                set: { v in
                    local = v
                    throttle { send(v) }
                }),
            range: range,
            enabled: enabled,
            onEditingChanged: { editing in
                releaseTask?.cancel()
                if editing { return }
                let final = local ?? remote
                (commit ?? send)(final)
                releaseTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    if !Task.isCancelled { local = nil }
                }
            })
    }
}
