import SwiftUI

/// The volume half of quick settings: output device, master, mic, and per-app volume with real app icons.
struct VolumeMixerPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "audio.mixer",
        title: "Volume Mixer",
        summary: "Master and per-app volume, microphone mute, and output device switching.",
        symbol: "speaker.wave.2",
        requires: "audio",
        sizes: [.small, .medium, .large, .banner, .wide],
        defaultSize: .banner,
        view: { AnyView(VolumeMixerPanel(ctx: $0)) })

    @Environment(\.fluent) private var theme

    var body: some View {
        if let a = ctx.state("audio", as: AudioState.self) {
            if ctx.size == .small { small(a) } else { full(a) }
        } else {
            PanelEmptyState(symbol: "speaker.slash", text: "Audio unavailable")
        }
    }

    private func small(_ a: AudioState) -> some View {
        VStack(spacing: 6) {
            if let out = a.output {
                Text("\(Int((out.volume * 100).rounded()))")
                    .font(FluentFont.titleLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(out.muted ? theme.textTertiary : theme.textPrimary)
                HStack(spacing: 4) {
                    FluentIconButton(symbol: "minus", size: 15, label: "Volume down") { ctx.run("audio", "setVolume", ["volume": .number(max(0, out.volume - 0.05))]) }
                    FluentIconButton(symbol: Self.speakerSymbol(out), size: 15, tint: out.muted ? theme.critical : nil, label: "Mute") { ctx.run("audio", "toggleMute") }
                    FluentIconButton(symbol: "plus", size: 15, label: "Volume up") { ctx.run("audio", "setVolume", ["volume": .number(min(1, out.volume + 0.05))]) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Quick settings sliders: the output device (with its picker), the microphone, then each app.
    /// Wide panels lay the rows out two across.
    private func full(_ a: AudioState) -> some View {
        let twoUp = ctx.size == .wide || ctx.size == .banner
        let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: twoUp ? 2 : 1)
        return GeometryReader { g in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    if let out = a.output {
                        VolumeRow(symbol: Self.speakerSymbol(out), icon: nil, title: out.name, volume: out.volume, muted: out.muted,
                                  onMute: { ctx.run("audio", "toggleMute") },
                                  onVolume: { v in ctx.send("audio", "setVolume", ["volume": .number(v)]) },
                                  trailing: AnyView(DevicePicker(ctx: ctx, audio: a)))
                    } else {
                        Text("No output device").font(FluentFont.caption).foregroundStyle(theme.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: Fluent.touchTarget, alignment: .leading)
                    }
                    if let mic = a.input {
                        VolumeRow(symbol: mic.muted ? "mic.slash" : "mic", icon: nil, title: mic.name, volume: mic.volume, muted: mic.muted,
                                  onMute: { ctx.run("audio", "toggleMicMute") },
                                  onVolume: { v in ctx.send("audio", "setMicVolume", ["volume": .number(v)]) })
                    }
                    ForEach(a.sessions) { s in
                        VolumeRow(symbol: s.icon == nil ? "speaker.wave.2" : nil, icon: s.icon, title: s.name, volume: s.volume, muted: s.muted,
                                  onMute: { ctx.run("audio", "toggleSessionMute", ["id": .string(s.id)]) },
                                  onVolume: { v in ctx.send("audio", "setSessionVolume", ["id": .string(s.id), "volume": .number(v)]) })
                            .opacity(s.active ? 1 : 0.7)
                    }
                }
                // Two-across rows sit in the middle of a shallow banner; a single column reads from the top.
                .frame(minHeight: g.size.height, alignment: twoUp ? .center : .top)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    static func speakerSymbol(_ e: AudioEndpointState) -> String {
        if e.muted || e.volume <= 0.001 { return "speaker.slash" }
        return e.volume < 0.33 ? "speaker.wave.1" : e.volume < 0.66 ? "speaker.wave.2" : "speaker.wave.3"
    }
}

/// Output device chooser: the chevron beside the volume slider in quick settings.
private struct DevicePicker: View {
    let ctx: PanelContext
    let audio: AudioState
    @Environment(\.fluent) private var theme

    var body: some View {
        FlyoutButton(width: 340, items: {
            [FlyoutItem.header("Sound output")] + audio.devices.map { d in
                FlyoutItem.action(d.name, checked: d.isDefault) {
                    ctx.run("audio", "setDefaultDevice", ["id": .string(d.id)])
                }
            }
        }) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 20, height: 36)
        }
        .accessibilityLabel("Sound output")
    }
}

private struct VolumeRow: View {
    let symbol: String?
    let icon: String?
    let title: String
    let volume: Double
    let muted: Bool
    let onMute: () -> Void
    let onVolume: (Double) -> Void
    /// Shown after the value. The slot is always reserved, so sliders line up down a column.
    var trailing: AnyView? = nil
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMute) {
                ZStack {
                    if let icon {
                        RemoteImage(path: icon, contentMode: .fit).frame(width: 24, height: 24)
                            .saturation(muted ? 0 : 1)
                            .opacity(muted ? 0.5 : 1)
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 17))
                    }
                    if muted && icon != nil {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.critical)
                            .offset(x: 11, y: 10)
                    }
                }
                .foregroundStyle(muted ? theme.critical : theme.textPrimary)
                .frame(width: 28, height: 40)
            }
            .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
            .accessibilityLabel(muted ? "Unmute \(title)" : "Mute \(title)")

            VStack(alignment: .leading, spacing: -8) {
                Text(title).font(.system(size: 12)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    .padding(.leading, 12)
                RemoteSlider(remote: volume, send: onVolume)
            }

            Text("\(Int((volume * 100).rounded()))")
                .font(FluentFont.body)
                .monospacedDigit()
                .foregroundStyle(muted ? theme.textTertiary : theme.textPrimary)
                .frame(width: 34, alignment: .trailing)

            ZStack { if let trailing { trailing } }
                .frame(width: 36)
        }
    }
}
