import SwiftUI

/// Which apps bring a board up: when one of them comes to the front on the PC, the iPad shows the
/// board, and goes back to the board you were on when you leave the app.
struct BoardAppsDialog: View {
    let boardID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    private var board: Board? { app.layout.boards.first { $0.id == boardID } }

    /// What's open on the PC now, then apps chosen earlier that aren't open.
    private var rows: [RunningApp] {
        let running = app.connection.store.box("apps").decoded(AppsState.self)?.running ?? []
        let open = Set(running.map(\.exe))
        let closed = chosen.subtracting(open).sorted().map {
            RunningApp(exe: $0, name: ($0 as NSString).deletingPathExtension, path: nil, icon: nil)
        }
        return running + closed
    }

    var body: some View {
        DialogSheet(title: "Show “\(board?.name ?? "Board")” for Apps", fills: true,
                    cancel: DialogAction("Cancel") { app.overlays.dismissDialog() },
                    confirm: DialogAction("Save") { save() }) {
            Text("When one of these apps comes to the front on the PC, this board shows up. Leave the app and the iPad goes back to the board you were on. Pick a tab yourself at any time to stay put.")
                .font(AppFont.body)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !app.settings.autoSwitchBoards {
                Banner(severity: .warning, title: "Switching boards is turned off in Settings.")
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(rows) { row in
                        appRow(row)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            guard !loaded else { return }
            chosen = Set(board?.apps ?? [])
            loaded = true
        }
    }

    private func appRow(_ row: RunningApp) -> some View {
        let on = chosen.contains(row.exe)
        return Button {
            if on { chosen.remove(row.exe) } else { chosen.insert(row.exe) }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon = row.icon {
                        RemoteImage(path: icon, contentMode: .fit) { Image(systemName: "app") }
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 20)).foregroundStyle(theme.textSecondary)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).font(AppFont.body).foregroundStyle(theme.textPrimary)
                    Text(row.path == nil ? "\(row.exe) · not open now" : row.exe)
                        .font(AppFont.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? theme.accent : theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(on ? theme.controlFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        app.layout.setApps(boardID, chosen.sorted())
        app.overlays.dismissDialog()
    }
}
