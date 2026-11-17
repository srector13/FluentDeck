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
        drawer: { AnyView(NowPlayingDrawer(ctx: $0)) },
        drawerSizes: [.medium],
        view: { AnyView(NowPlayingPanel(ctx: $0)) })

    @Environment(\.theme) private var theme

    var body: some View {
        if let m = ctx.state("media", as: MediaState.self), m.hasSession {
            switch ctx.size {
            case .medium: medium(m)
            case .wide: wide(m)
            default: centered(m)
            }
        } else {
            VStack(spacing: 12) {
                PanelEmptyState(symbol: "music.note", text: "Nothing is playing")
                TransportRow(ctx: ctx, media: nil, prominent: false)
            }
        }
    }

    /// Large and tall: everything on the centre line — source, cover, title, artist and album,
    /// scrubber and transport — like a record sleeve.
    private func centered(_ m: MediaState) -> some View {
        VStack(spacing: 0) {
            SourcePicker(ctx: ctx, media: m)
            Artwork(path: m.artwork, radius: Metrics.artRadius)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 10)
            Text(m.title ?? "Unknown title")
                .font(AppFont.subtitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 14)
            Text([m.artist, m.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                .font(AppFont.body)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
            Scrubber(ctx: ctx, media: m)
                .padding(.top, 8)
            TransportRow(ctx: ctx, media: m, prominent: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func medium(_ m: MediaState) -> some View {
        HStack(spacing: 14) {
            Artwork(path: m.artwork).aspectRatio(1, contentMode: .fit).frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title ?? "Unknown title").font(AppFont.bodyStrong).lineLimit(1)
                Text(m.artist ?? "").font(AppFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
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
                Text(m.title ?? "Unknown title").font(AppFont.title).lineLimit(2).minimumScaleFactor(0.7)
                Text([m.artist, m.album].compactMap { $0 }.joined(separator: " — "))
                    .font(AppFont.bodyLarge).foregroundStyle(theme.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                Scrubber(ctx: ctx, media: m)
                TransportRow(ctx: ctx, media: m, prominent: true)
            }
            .foregroundStyle(theme.textPrimary)
        }
    }
}

/// The compact player's drawer: large cover, source, scrubber and the full transport.
struct NowPlayingDrawer: View {
    let ctx: PanelContext
    @Environment(\.theme) private var theme

    var body: some View {
        if let m = ctx.state("media", as: MediaState.self), m.hasSession {
            HStack(alignment: .top, spacing: 28) {
                Artwork(path: m.artwork, radius: Metrics.artRadius)
                    .frame(width: 220, height: 220)
                VStack(alignment: .leading, spacing: 4) {
                    SourcePicker(ctx: ctx, media: m)
                    Text(m.title ?? "Unknown title")
                        .font(AppFont.title)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text([m.artist, m.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(AppFont.bodyLarge)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Scrubber(ctx: ctx, media: m)
                    TransportRow(ctx: ctx, media: m, prominent: true)
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 220)
        } else {
            PanelEmptyState(symbol: "music.note", text: "Nothing is playing").frame(height: 120)
        }
    }
}

private struct Artwork: View {
    let path: String?
    var radius: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        RemoteImage(path: path) {
            ZStack {
                theme.controlFill
                Image(systemName: "music.note").font(.system(size: 28, weight: .light)).foregroundStyle(theme.textTertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }
}

/// Which app is playing — tap to switch between media sessions.
private struct SourcePicker: View {
    let ctx: PanelContext
    let media: MediaState
    @Environment(\.theme) private var theme

    var body: some View {
        ActionMenu(items: {
            [ActionItem.header("Playing on the PC")] + media.sessions.map { s in
                ActionItem.action(s.name, checked: s.appId == media.source?.appId) {
                    ctx.run("media", "selectSession", ["appId": .string(s.appId)])
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 12))
                Text(media.source?.name ?? "Media").font(AppFont.caption).lineLimit(1)
                if media.sessions.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)) }
            }
            .foregroundStyle(theme.textSecondary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .disabled(media.sessions.count < 2)
    }
}

/// Live position (interpolated locally) with a seekable slider.
private struct Scrubber: View {
    let ctx: PanelContext
    let media: MediaState
    @Environment(\.theme) private var theme
    @State private var scrub: Double?

    var body: some View {
        let received = ctx.box("media").receivedAt
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let live = media.isPlaying ? media.position + timeline.date.timeIntervalSince(received) : media.position
            let position = min(max(scrub ?? live, 0), max(media.duration, 0))
            VStack(spacing: 0) {
                PillSlider(
                    value: Binding(get: { position }, set: { scrub = $0 }),
                    range: 0...max(media.duration, 1),
                    enabled: media.canSeek,
                    thickness: 7,
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
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .offset(y: -8)
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
    @Environment(\.theme) private var theme

    var body: some View {
        let m = media
        HStack(spacing: prominent ? 10 : 2) {
            if prominent, m?.canShuffle == true {
                IconButton(symbol: "shuffle", size: 15, tint: m?.shuffle == true ? theme.accent : theme.textSecondary, label: "Shuffle") {
                    ctx.run("media", "shuffle", ["on": .bool(!(m?.shuffle ?? false))])
                }
            }
            if prominent { Spacer(minLength: 0) }
            IconButton(symbol: "backward.fill", size: prominent ? 19 : 15, label: "Previous") { ctx.run("media", "previous") }
                .disabled(m != nil && m?.canPrevious == false)
            PlayPauseButton(playing: m?.isPlaying ?? false, prominent: prominent) { ctx.run("media", "playPause") }
            IconButton(symbol: "forward.fill", size: prominent ? 19 : 15, label: "Next") { ctx.run("media", "next") }
                .disabled(m != nil && m?.canNext == false)
            if prominent { Spacer(minLength: 0) }
            if prominent, m?.canRepeat == true {
                let mode = m?.`repeat` ?? "none"
                IconButton(symbol: mode == "track" ? "repeat.1" : "repeat", size: 15,
                                 tint: mode == "none" ? theme.textSecondary : theme.accent, label: "Repeat") {
                    ctx.run("media", "repeat")
                }
            }
        }
        .padding(.horizontal, prominent ? -18 : 0) // outer glyphs meet the widget's edges
        .frame(maxWidth: .infinity, alignment: prominent ? .center : .leading)
    }
}

private struct PlayPauseButton: View {
    let playing: Bool
    let prominent: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: prominent ? 22 : 16))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 56 : 40, height: prominent ? 56 : 40)
        }
        .buttonStyle(CircleFillStyle())
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

/// The play button: a white disc with a dark glyph, as in the iOS players.
private struct CircleFillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { CircleBody(configuration: configuration) }

    struct CircleBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.theme) private var theme
        var body: some View {
            configuration.label
                .foregroundStyle(.black)
                .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.75 : 1)))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
        }
    }
}
