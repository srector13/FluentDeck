import SwiftUI

/// Now Playing — whatever Windows' media flyout shows (Spotify, Apple Music, browsers…).
struct NowPlayingPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "media.nowPlaying",
        title: "Now Playing",
        summary: "Album art, playback controls and a scrubber for whatever is playing on the PC.",
        symbol: "music.note",
        requires: "media",
        sizes: [.medium, .large, .tall, .wide],
        defaultSize: .tall,
        view: { AnyView(NowPlayingPanel(ctx: $0)) })

    @Environment(\.fluent) private var theme

    var body: some View {
        if let m = ctx.state("media", as: MediaState.self), m.hasSession {
            switch ctx.size {
            case .medium: medium(m)
            case .tall: tall(m)
            case .wide: wide(m)
            default: large(m)
            }
        } else {
            VStack(spacing: 12) {
                PanelEmptyState(symbol: "music.note", text: "Nothing is playing")
                TransportRow(ctx: ctx, media: nil, prominent: false)
            }
        }
    }

    private func large(_ m: MediaState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Artwork(path: m.artwork).frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title ?? "Unknown title").font(FluentFont.bodyLarge.weight(.semibold)).lineLimit(2)
                    Text(m.artist ?? "").font(FluentFont.body).foregroundStyle(theme.textSecondary).lineLimit(1)
                    SourcePicker(ctx: ctx, media: m).padding(.top, 4)
                }
                .foregroundStyle(theme.textPrimary)
            }
            Spacer(minLength: 0)
            Scrubber(ctx: ctx, media: m)
            TransportRow(ctx: ctx, media: m, prominent: true)
        }
    }

    /// The Windows media flyout, stood upright: source, cover, title, scrubber, transport.
    /// The cover throws its colours onto the black around it.
    private func tall(_ m: MediaState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SourcePicker(ctx: ctx, media: m)
            Artwork(path: m.artwork, radius: Fluent.artRadius, glow: true)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
                .zIndex(-1) // its glow falls behind the text above and below
            Text(m.title ?? "Unknown title")
                .font(FluentFont.subtitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 14)
            Text(m.artist ?? "")
                .font(FluentFont.body)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .padding(.top, 2)
            Scrubber(ctx: ctx, media: m)
                .padding(.top, 2)
            TransportRow(ctx: ctx, media: m, prominent: true)
        }
    }

    private func medium(_ m: MediaState) -> some View {
        HStack(spacing: 14) {
            Artwork(path: m.artwork).aspectRatio(1, contentMode: .fit).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title ?? "Unknown title").font(FluentFont.bodyStrong).lineLimit(1)
                Text(m.artist ?? "").font(FluentFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                Spacer(minLength: 4)
                TransportRow(ctx: ctx, media: m, prominent: false)
            }
            .foregroundStyle(theme.textPrimary)
        }
    }

    private func wide(_ m: MediaState) -> some View {
        HStack(spacing: 22) {
            Artwork(path: m.artwork).aspectRatio(1, contentMode: .fit).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                SourcePicker(ctx: ctx, media: m)
                Text(m.title ?? "Unknown title").font(FluentFont.title).lineLimit(2).minimumScaleFactor(0.7)
                Text([m.artist, m.album].compactMap { $0 }.joined(separator: " — "))
                    .font(FluentFont.bodyLarge).foregroundStyle(theme.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                Scrubber(ctx: ctx, media: m)
                TransportRow(ctx: ctx, media: m, prominent: true)
            }
            .foregroundStyle(theme.textPrimary)
        }
    }
}

private struct Artwork: View {
    let path: String?
    var radius: CGFloat = 14
    /// A soft halo of the cover's own colours behind it.
    var glow = false
    @Environment(\.fluent) private var theme

    var body: some View {
        RemoteImage(path: path) {
            ZStack {
                theme.controlFill
                Image(systemName: "music.note").font(.system(size: 28, weight: .light)).foregroundStyle(theme.textTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .background {
            if glow, path != nil {
                RemoteImage(path: path)
                    .blur(radius: 48)
                    .saturation(1.3)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Which app is playing — tap to switch between media sessions.
private struct SourcePicker: View {
    let ctx: PanelContext
    let media: MediaState
    @Environment(\.fluent) private var theme

    var body: some View {
        FlyoutButton(width: 280, items: {
            [FlyoutItem.header("Playing on the PC")] + media.sessions.map { s in
                FlyoutItem.action(s.name, checked: s.appId == media.source?.appId) {
                    ctx.run("media", "selectSession", ["appId": .string(s.appId)])
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 12))
                Text(media.source?.name ?? "Media").font(FluentFont.caption).lineLimit(1)
                if media.sessions.count > 1 { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            }
            .foregroundStyle(theme.textSecondary)
        }
        .disabled(media.sessions.count < 2)
        .padding(.leading, -8)
    }
}

/// Live position (interpolated locally) with a seekable slider.
private struct Scrubber: View {
    let ctx: PanelContext
    let media: MediaState
    @Environment(\.fluent) private var theme
    @State private var scrub: Double?

    var body: some View {
        let received = ctx.box("media").receivedAt
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let live = media.isPlaying ? media.position + timeline.date.timeIntervalSince(received) : media.position
            let position = min(max(scrub ?? live, 0), max(media.duration, 0))
            VStack(spacing: 0) {
                FluentSlider(
                    value: Binding(get: { position }, set: { scrub = $0 }),
                    range: 0...max(media.duration, 1),
                    enabled: media.canSeek,
                    onEditingChanged: { editing in
                        guard !editing, let target = scrub else { return }
                        ctx.run("media", "seek", ["seconds": .number(target)])
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            scrub = nil
                        }
                    })
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(media.duration > 0 ? "-" + Self.format(media.duration - position) : "")
                }
                .font(FluentFont.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .offset(y: -6)
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct TransportRow: View {
    let ctx: PanelContext
    let media: MediaState?
    var prominent: Bool
    @Environment(\.fluent) private var theme

    var body: some View {
        let m = media
        HStack(spacing: prominent ? 10 : 2) {
            if prominent, m?.canShuffle == true {
                FluentIconButton(symbol: "shuffle", size: 15, tint: m?.shuffle == true ? theme.accent : theme.textSecondary, label: "Shuffle") {
                    ctx.run("media", "shuffle", ["on": .bool(!(m?.shuffle ?? false))])
                }
            }
            if prominent { Spacer(minLength: 0) }
            FluentIconButton(symbol: "backward.fill", size: prominent ? 19 : 15, label: "Previous") { ctx.run("media", "previous") }
                .disabled(m != nil && m?.canPrevious == false)
            PlayPauseButton(playing: m?.isPlaying ?? false, prominent: prominent) { ctx.run("media", "playPause") }
            FluentIconButton(symbol: "forward.fill", size: prominent ? 19 : 15, label: "Next") { ctx.run("media", "next") }
                .disabled(m != nil && m?.canNext == false)
            if prominent { Spacer(minLength: 0) }
            if prominent, m?.canRepeat == true {
                let mode = m?.`repeat` ?? "none"
                FluentIconButton(symbol: mode == "track" ? "repeat.1" : "repeat", size: 15,
                                 tint: mode == "none" ? theme.textSecondary : theme.accent, label: "Repeat") {
                    ctx.run("media", "repeat")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: prominent ? .center : .leading)
    }
}

private struct PlayPauseButton: View {
    let playing: Bool
    let prominent: Bool
    let action: () -> Void
    @Environment(\.fluent) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: prominent ? 22 : 16))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 56 : 40, height: prominent ? 56 : 40)
        }
        .buttonStyle(CircleAccentStyle())
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

private struct CircleAccentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CircleBody(configuration: configuration) }

    struct CircleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.fluent) private var theme
        var body: some View {
            configuration.label
                .foregroundStyle(theme.textOnAccent)
                .background(Circle().fill(configuration.isPressed ? theme.accentTertiary : theme.accent))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}
