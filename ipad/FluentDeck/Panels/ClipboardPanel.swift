import SwiftUI
import UIKit

/// Text between the iPad and the PC: send what's copied on the iPad (or paste it straight into the
/// app in front), or bring the PC's clipboard over to the iPad.
struct ClipboardPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "clipboard",
        title: "Clipboard",
        summary: "Send text copied on the iPad to the PC's clipboard, or paste it straight into the app in front. Or copy the PC's clipboard to the iPad.",
        symbol: "doc.on.clipboard",
        requires: "clipboard",
        sizes: [.small, .medium, .large],
        defaultSize: .medium,
        view: { AnyView(ClipboardPanel(ctx: $0)) })

    @Environment(\.theme) private var theme
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        let compact = ctx.size == .small
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 14))
                    Text(status ?? "Clipboard").font(AppFont.caption).lineLimit(1)
                }
                .foregroundStyle(theme.textSecondary)
                .animation(.easeOut, value: status)
            }
            let layout = ctx.size == .medium ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))
            layout {
                action("Send to PC", symbol: "arrow.up.doc", compact: compact) { send(paste: false) }
                action("Paste on PC", symbol: "doc.on.clipboard", compact: compact) { send(paste: true) }
                action("Copy from PC", symbol: "arrow.down.doc", compact: compact) { fetch() }
            }
            .frame(maxHeight: .infinity)
        }
        .disabled(busy)
    }

    private func action(_ title: String, symbol: String, compact: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: compact ? 16 : 20, weight: .medium))
                if !compact {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.controlFill))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(DimOnPress())
        .accessibilityLabel(title)
    }

    /// Reading the iPad's clipboard makes iOS ask "Allow Paste" unless allowed in Settings.
    private func send(paste: Bool) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            status = "Nothing to send: copy some text on the iPad first"
            return
        }
        run(paste ? "Pasted \(Self.describe(text)) on the PC" : "Sent \(Self.describe(text)) to the PC") {
            _ = try await ctx.connection.invoke("clipboard", "setText", ["text": .string(text), "paste": .bool(paste)])
        }
    }

    private func fetch() {
        run(nil) {
            let result = try await ctx.connection.invoke("clipboard", "getText")
            let text = result?["text"]?.string ?? ""
            if text.isEmpty {
                status = "The PC's clipboard has no text"
            } else {
                UIPasteboard.general.string = text
                status = "Copied \(Self.describe(text)) from the PC"
            }
        }
    }

    private func run(_ done: String?, _ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task { @MainActor in
            do {
                try await work()
                if let done { status = done }
            } catch {
                ctx.connection.report(error)
            }
            busy = false
        }
    }

    /// "12 characters", or the text itself if it's short.
    static func describe(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.count <= 24 ? "“\(oneLine)”" : "\(text.count) characters"
    }
}

/// A plain button that dims while pressed.
struct DimOnPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
