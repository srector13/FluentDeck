import SwiftUI

/// Shown when the PC doesn't know this iPad yet: enter the 6-digit code from the tray app.
struct PairingDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var code = ""
    @State private var submitted = false

    private var reason: String? {
        if case .needsPairing(let reason) = app.connection.phase { return reason }
        return nil
    }

    var body: some View {
        ZStack {
            theme.smoke.ignoresSafeArea()
            DialogSheet(title: "Pair with \(app.connection.hostName)",
                        cancel: DialogAction("Cancel") { app.cancelConnect() },
                        confirm: DialogAction("Pair", enabled: code.count == 6, perform: pair)) {
                Text("On the PC, click the FluentDeck icon in the system tray and choose **Pair new device…**, then type the code it shows.")
                    .font(AppFont.body)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextBox(placeholder: "000 000", text: $code, keyboard: .numberPad, contentType: .oneTimeCode, large: true, onSubmit: pair)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 && !submitted { pair() }
                        if digits.count < 6 { submitted = false }
                    }
                if let reason {
                    Banner(severity: submitted ? .error : .informational, title: reason)
                }
            }
            .frame(maxWidth: 460)
            .background(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(.regularMaterial))
            .padding(24)
        }
    }

    private func pair() {
        guard code.count == 6 else { return }
        submitted = true
        app.connection.pair(code: code)
    }
}
