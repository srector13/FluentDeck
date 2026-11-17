import SwiftUI

/// Volume, as Control Center sliders: output device, master, mic, and per-app volume with real app icons.
/// The compact sizes show the output and the microphone; their drawer has every app.
struct VolumeMixerPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "audio.mixer",
        title: "Volume Mixer",
        summary: "Output and microphone volume at a glance. Slide the handle up for each app’s volume and the output device.",
        symbol: "speaker.wave.2",
        requires: "audio",
        sizes: [.small, .medium, .large, .banner, .wide],
        defaultSize: .medium,
        drawer: { AnyView(VolumeMixerDrawer(ctx: $0)) },
        drawerSizes: [.small, .medium],
        view: { AnyView(VolumeMixerPanel(ctx: $0)) })

    @Environment(\.theme) private var theme

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
                    .font(AppFont.titleLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(out.muted ? theme.textTertiary : theme.textPrimary)
                HStack(spacing: 4) {
                    IconButton(symbol: "minus", size: 15, label: "Volume down") { ctx.run("audio", "setVolume", ["volume": .number(max(0, out.volume - 0.05))]) }
                    IconButton(symbol: Self.speakerSymbol(out), size: 15, tint: out.muted ? theme.critical : nil, label: "Mute") { ctx.run("audio", "toggleMute") }
                    IconButton(symbol: "plus", size: 15, label: "Volume up") { ctx.run("audio", "setVolume", ["volume": .number(min(1, out.volume + 0.05))]) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The slider rows: the output device (its name opens the picker), the microphone, then each app.
    /// Wide panels lay the rows out two across. The medium size stops after the microphone.
    private func full(_ a: AudioState) -> some View {
        let twoUp = ctx.size == .wide || ctx.size == .banner
        let compact = ctx.size == .medium
        return GeometryReader { g in
            ScrollView {
                MixerRows(ctx: ctx, audio: a, apps: !compact, columns: twoUp ? 2 : 1)
                    // Rows sit in the middle of a shallow panel; a tall single column reads from the top.
                    .frame(minHeight: g.size.height, alignment: twoUp || compact ? .center : .top)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(compact)
        }
    }

    static func speakerSymbol(_ e: AudioEndpointState) -> String {
        if e.muted || e.volume <= 0.001 { return "speaker.slash" }
        return e.volume < 0.33 ? "speaker.wave.1" : e.volume < 0.66 ? "speaker.wave.2" : "speaker.wave.3"
    }
}

/// The slider rows: output, microphone and, if asked, one per app playing sound.
private struct MixerRows: View {
    let ctx: PanelContext
    let audio: AudioState
    var apps = true
    var columns = 1
    @Environment(\.theme) private var theme

    /// Height of one row, for views that size themselves to the rows.
    static let rowHeight: CGFloat = 54

    static func count(_ audio: AudioState, apps: Bool = true) -> Int {
        1 + (audio.input == nil ? 0 : 1) + (apps ? audio.sessions.count : 0)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 36), count: columns), spacing: 2) {
            if let out = audio.output {
                VolumeRow(symbol: VolumeMixerPanel.speakerSymbol(out), icon: nil, title: out.name, volume: out.volume, muted: out.muted,
                          onMute: { ctx.run("audio", "toggleMute") },
                          onVolume: { v in ctx.send("audio", "setVolume", ["volume": .number(v)]) },
                          menu: {
                              [ActionItem.header("Sound output")] + audio.devices.map { d in
                                  ActionItem.action(d.name, checked: d.isDefault) {
                                      ctx.run("audio", "setDefaultDevice", ["id": .string(d.id)])
                                  }
                              }
                          })
            } else {
                Text("No output device").font(AppFont.caption).foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: Metrics.touchTarget, alignment: .leading)
            }
            if let mic = audio.input {
                VolumeRow(symbol: mic.muted ? "mic.slash" : "mic", icon: nil, title: mic.name, volume: mic.volume, muted: mic.muted,
                          onMute: { ctx.run("audio", "toggleMicMute") },
                          onVolume: { v in ctx.send("audio", "setMicVolume", ["volume": .number(v)]) })
            }
            if apps {
                ForEach(audio.sessions) { s in
                    VolumeRow(symbol: s.icon == nil ? "speaker.wave.2" : nil, icon: s.icon, title: s.name, volume: s.volume, muted: s.muted,
                              onMute: { ctx.run("audio", "toggleSessionMute", ["id": .string(s.id)]) },
                              onVolume: { v in ctx.send("audio", "setSessionVolume", ["id": .string(s.id), "volume": .number(v)]) })
                        .opacity(s.active ? 1 : 0.7)
                }
            }
        }
    }
}

/// The mixer's drawer: every slider, two across, as tall as its rows need.
struct VolumeMixerDrawer: View {
    let ctx: PanelContext

    var body: some View {
        if let audio = ctx.state("audio", as: AudioState.self) {
            let rows = (MixerRows.count(audio) + 1) / 2
            ScrollView {
                MixerRows(ctx: ctx, audio: audio, columns: 2)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(CGFloat(rows) * MixerRows.rowHeight + 8, 430))
        } else {
            PanelEmptyState(symbol: "speaker.slash", text: "Audio unavailable").frame(height: 120)
        }
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
    /// When set, the title opens this menu (the output device picker).
    var menu: (() -> [ActionItem])? = nil
    @Environment(\.theme) private var theme

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
            .buttonStyle(PillButtonStyle(kind: .subtle, compact: true))
            .accessibilityLabel(muted ? "Unmute \(title)" : "Mute \(title)")

            VStack(alignment: .leading, spacing: -5) {
                if let menu {
                    ActionMenu(items: menu) {
                        HStack(spacing: 5) {
                            Text(title).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.leading, 2)
                        .padding(.vertical, 10) // a taller touch target than the text
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, -10)
                    .zIndex(1)
                    .accessibilityLabel("Sound output: \(title)")
                } else {
                    Text(title).font(.system(size: 12)).foregroundStyle(theme.textSecondary).lineLimit(1)
                        .padding(.leading, 2)
                }
                RemoteSlider(remote: volume, send: onVolume)
            }

            Text("\(Int((volume * 100).rounded()))")
                .font(AppFont.body)
                .monospacedDigit()
                .foregroundStyle(muted ? theme.textTertiary : theme.textPrimary)
                .frame(width: 34, alignment: .trailing)

        }
        .padding(.leading, -8) // the icon, not its touch target, lines up with the widget's edge
    }
}
