import SwiftUI

/// Windows' virtual desktops: one button for each, the one showing lit. Tap one to go there, even
/// from a full-screen remote desktop.
struct DesktopsPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "desktops",
        title: "Desktops",
        summary: "Your PC's virtual desktops by name, with the one on screen lit. Tap one to switch to it — handy when a full-screen remote desktop lives on its own desktop.",
        symbol: "rectangle.split.3x1",
        requires: "desktops",
        sizes: [.small, .medium, .banner],
        defaultSize: .medium,
        view: { AnyView(DesktopsPanel(ctx: $0)) })

    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let state = ctx.state("desktops", as: DesktopsState.self), !state.desktops.isEmpty {
            GeometryReader { g in
                let across = g.size.width > g.size.height * 1.4
                let layout = across ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    ForEach(state.desktops) { desktop in
                        button(desktop, current: desktop.index == state.current)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        } else {
            PanelEmptyState(symbol: "rectangle.split.3x1", text: "Desktops unavailable")
        }
    }

    private func button(_ desktop: DesktopsState.Desktop, current: Bool) -> some View {
        let fill = settings.litKeysUseAccent ? theme.accent : Color.white
        let ink: Color = current ? (settings.litKeysUseAccent ? theme.textOnAccent : .black) : theme.textPrimary
        return Button {
            ctx.run("desktops", "switch", ["index": .number(Double(desktop.index))])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: desktop.index <= 50 ? "\(desktop.index).square.fill" : "rectangle.fill")
                    .font(.system(size: 17, weight: .medium))
                Text(desktop.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(current ? fill : theme.controlFill))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityLabel("Switch to \(desktop.name)")
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
