import SwiftUI

/// A Control Center slider: a capsule that fills from the left, with no thumb. Drag or tap anywhere
/// on it (the touch area is 44 pt tall whatever the bar's thickness). It swells a little while held.
struct PillSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var enabled = true
    /// Height of the bar at rest: thick for volume, thin for a scrubber.
    var thickness: CGFloat = 28
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.theme) private var theme
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let width = max(g.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, .ulpOfOne)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                theme.controlFill
                (enabled ? Color.white : theme.textDisabled)
                    .frame(width: width * fraction)
            }
            .frame(height: dragging ? thickness + min(6, thickness * 0.5) : thickness)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        if !dragging { dragging = true; TouchArbiter.sliderActive = true; onEditingChanged(true) }
                        let f = min(max(drag.location.x / width, 0), 1)
                        value = range.lowerBound + f * span
                    }
                    .onEnded { _ in
                        TouchArbiter.sliderActive = false
                        guard enabled else { return }
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.snappy(duration: 0.15), value: dragging)
        }
        .frame(height: Metrics.touchTarget)
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
    var thickness: CGFloat = 28
    let send: (Double) -> Void
    var commit: ((Double) -> Void)? = nil

    @State private var local: Double?
    @State private var throttle = Throttle()
    @State private var releaseTask: Task<Void, Never>?

    var body: some View {
        PillSlider(
            value: Binding(
                get: { local ?? remote },
                set: { v in
                    local = v
                    throttle { send(v) }
                }),
            range: range,
            enabled: enabled,
            thickness: thickness,
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
