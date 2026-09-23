import SwiftUI

struct StatusBar: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var connection: ConnectionManager
    @EnvironmentObject private var dialUp: DialUpPanelController
    @ObservedObject var engine: BrowserSimulator

    var body: some View {
        let theme = settings.skin.theme

        HStack(spacing: 12) {
            Text(engine.downloadStatus ?? engine.statusText)
                .font(.system(size: 12))
                .foregroundColor(theme.statusForeground)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            ProgressView(value: engine.progress)
                .tint(theme.progressTint)
                .frame(width: 170)
                .opacity(engine.isLoading ? 1 : 0.45)

            ConnectionButton(
                connection: connection,
                dialUp: dialUp,
                theme: theme,
                maximumSpeed: settings.maxModemSpeed
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(chromeBackground(theme: theme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.bevelEdge)
                .frame(height: 1)
        }
    }

    private func chromeBackground(theme: SkinTheme) -> AnyShapeStyle {
        if theme.chromeFlat {
            return AnyShapeStyle(theme.toolbarTop)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [theme.toolbarTop, theme.toolbarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct ConnectionButton: View {
    @ObservedObject var connection: ConnectionManager
    let dialUp: DialUpPanelController
    let theme: SkinTheme
    let maximumSpeed: Int

    var body: some View {
        Button(action: handle) {
            HStack(spacing: 6) {
                Image(systemName: connection.isConnected ? "phone.fill" : "phone")
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(theme.buttonForeground)
        }
        .buttonStyle(BevelButtonStyle(theme: theme))
    }

    private var title: String {
        switch connection.state {
        case .idle: "Подключить"
        case .dialing, .waitingForCarrier, .handshaking,
             .verifyingIdentity, .assigningAddress: "Соединение…"
        case .connected: "Онлайн"
        case .disconnecting: "Отключение…"
        case .error: "Переподключить"
        }
    }

    private func handle() {
        connection.connect(maximumSpeed: maximumSpeed)
        dialUp.show()
    }
}