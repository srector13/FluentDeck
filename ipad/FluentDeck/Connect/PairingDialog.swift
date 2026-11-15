import SwiftUI

/// Shown when the PC doesn't know this iPad yet: enter the 6-digit code from the tray app.
struct PairingDialog: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme
    @State private var code = ""
    @State private var submitted = false

    private var reason: String? {
        if case .needsPairing(let reason) = app.connection.phase { return reason }
        return nil
    }

    var body: some View {
        ZStack {
            theme.smoke.ignoresSafeArea()
            ContentDialog(title: "Pair with \(app.connection.hostName)") {
                Text("On the PC, click the FluentDeck icon in the system tray and choose **Pair new device…**, then type the code it shows.")
                    .font(FluentFont.body)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FluentTextBox(placeholder: "000 000", text: $code, keyboard: .numberPad, contentType: .oneTimeCode, large: true, onSubmit: pair)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(6))
                        if digits != new { code = digits }
                        if digits.count == 6 && !submitted { pair() }
                        if digits.count < 6 { submitted = false }
                    }
                if let reason {
                    InfoBar(severity: submitted ? .error : .informational, title: reason)
                }
            } footer: {
                DialogButton(title: "Pair", accent: true, enabled: code.count == 6, action: pair)
                DialogButton(title: "Cancel") { app.cancelConnect() }
            }
            .padding(24)
        }
    }

    private func pair() {
        guard code.count == 6 else { return }
        submitted = true
        app.connection.pair(code: code)
    }
}
