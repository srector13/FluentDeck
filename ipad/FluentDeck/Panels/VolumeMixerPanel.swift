import SwiftUI

/// Windows 11 volume mixer: output device, master, mic, and per-app volume with real app icons.
struct VolumeMixerPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "audio.mixer",
        title: "Volume Mixer",
        summary: "Master and per-app volume, microphone mute, and output device switching.",
        symbol: "speaker.wave.2",
        requires: "audio",
        sizes: [.small, .medium, .large, .wide],
        defaultSize: .large,
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

    private func full(_ a: AudioState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DevicePicker(ctx: ctx, audio: a)
            if let out = a.output {
                VolumeRow(symbol: Self.speakerSymbol(out), icon: nil, title: nil, volume: out.volume, muted: out.muted,
                          onMute: { ctx.run("audio", "toggleMute") },
                          onVolume: { v in ctx.send("audio", "setVolume", ["volume": .number(v)]) })
            }
            if let mic = a.input {
                VolumeRow(symbol: mic.muted ? "mic.slash" : "mic", icon: nil, title: nil, volume: mic.volume, muted: mic.muted,
                          onMute: { ctx.run("audio", "toggleMicMute") },
                          onVolume: { v in ctx.send("audio", "setMicVolume", ["volume": .number(v)]) })
            }
            if ctx.size == .large || ctx.size == .wide {
                Text("Apps")
                    .font(FluentFont.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 6)
                ScrollView {
                    LazyVGrid(columns: ctx.size == .wide ? [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)] : [GridItem(.flexible())],
                              spacing: 0) {
                        ForEach(a.sessions) { s in
                            VolumeRow(symbol: s.icon == nil ? "speaker.wave.2" : nil, icon: s.icon, title: s.name, volume: s.volume, muted: s.muted,
                                      onMute: { ctx.run("audio", "toggleSessionMute", ["id": .string(s.id)]) },
                                      onVolume: { v in ctx.send("audio", "setSessionVolume", ["id": .string(s.id), "volume": .number(v)]) })
                                .opacity(s.active ? 1 : 0.7)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if a.sessions.isEmpty {
                    Text("No apps are playing sound").font(FluentFont.caption).foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    static func speakerSymbol(_ e: AudioEndpointState) -> String {
        if e.muted || e.volume <= 0.001 { return "speaker.slash" }
        return e.volume < 0.33 ? "speaker.wave.1" : e.volume < 0.66 ? "speaker.wave.2" : "speaker.wave.3"
    }
}

/// Output device chooser, like the "Sound output" chevron in Quick Settings.
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
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker").font(.system(size: 13))
                Text(audio.output?.name ?? "No output device").font(FluentFont.caption).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary)
        }
        .padding(.leading, -8)
    }
}

private struct VolumeRow: View {
    let symbol: String?
    let icon: String?
    let title: String?
    let volume: Double
    let muted: Bool
    let onMute: () -> Void
    let onVolume: (Double) -> Void
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onMute) {
                ZStack {
                    if let icon {
                        RemoteImage(path: icon, contentMode: .fit).frame(width: 26, height: 26)
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
                .frame(width: 40, height: 40)
            }
            .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
            .accessibilityLabel(muted ? "Unmute" : "Mute")

            VStack(alignment: .leading, spacing: -10) {
                if let title {
                    Text(title).font(FluentFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                        .padding(.leading, 12)
                }
                RemoteSlider(remote: volume, send: onVolume)
            }

            Text("\(Int((volume * 100).rounded()))")
                .font(FluentFont.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(muted ? theme.textTertiary : theme.textPrimary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
