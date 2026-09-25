import SwiftUI

struct DialUpStatusView: View {
    @EnvironmentObject private var connection: ConnectionManager

    var onDebugToggle: (Bool) -> Void = { _ in }
    @State private var showDebug = false

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private var theme: SkinTheme { AppSkin.cheesecake.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0, green: 0.35, blue: 0.5))
                Text("RetroSurf ISP")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.64, green: 0.69, blue: 0.78))

            HStack(alignment: .top, spacing: 16) {
                DialUpMonitors(
                    txFlash: connection.txFlash,
                    rxFlash: connection.rxFlash,
                    handshaking: connection.isHandshaking
                )
                VStack(alignment: .leading, spacing: 5) {
                    infoRow("Статус:", connection.state.statusText)
                    if case .connected(let speed) = connection.state {
                        infoRow("Скорость:", "\(Self.format(speed)) бит/с")
                    }
                    infoRow("Отправлено:", "\(Self.format(connection.bytesSent)) байт")
                    infoRow("Получено:", "\(Self.format(connection.bytesReceived)) байт")
                    infoRow("Обрывов:", "\(Self.format(connection.errorCount))")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

#if DEBUG
            if showDebug {
                debugConsole
                Divider()
            }
#endif

            HStack {
                #if DEBUG
                Button(showDebug ? "Скрыть отладку" : "Отладка…") {
                    showDebug.toggle()
                }
                .buttonStyle(BevelButtonStyle(theme: theme))
                #endif
                Spacer()
                Button("Разъединить") {
                    connection.disconnect()
                }
                .disabled(!connection.isConnected)
                .buttonStyle(BevelButtonStyle(theme: theme))
                .opacity(connection.isConnected ? 1 : 0.5)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .padding(.top, 6)
        .frame(width: 400)
        .background(Color(red: 0.75, green: 0.75, blue: 0.78))
        .onChange(of: showDebug) { value in
            onDebugToggle(value)
        }
    }

#if DEBUG
    private var debugConsole: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG · журнал переходов")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.green)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if connection.debugLog.isEmpty {
                        Text("(пока нет переходов)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color.green.opacity(0.6))
                    } else {
                        ForEach(Array(connection.debugLog.suffix(15).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.green)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.04, green: 0.06, blue: 0.04))
        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 1))
    }
#endif

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
    }

    private static func format(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct DialUpMonitors: View {
    let txFlash: Bool
    let rxFlash: Bool
    let handshaking: Bool

    var body: some View {
        VStack(spacing: 12) {
            Monitor(label: "TX", led: .yellow, flashActive: txFlash, handshaking: handshaking)
            Monitor(label: "RX", led: .green, flashActive: rxFlash, handshaking: handshaking)
        }
    }
}

private struct Monitor: View {
    let label: String
    let led: Color
    let flashActive: Bool
    let handshaking: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.72), Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 62)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(white: 0.3), lineWidth: 1))
                screen(glowActive: flashActive || handshaking)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let interval = context.date.timeIntervalSinceReferenceDate
                let blinkOn = interval.truncatingRemainder(dividingBy: 1.0) < 0.5
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(isLedLit(blinkOn: blinkOn))
                        .frame(width: 10, height: 7)
                        .overlay(Rectangle().stroke(Color(white: 0.25), lineWidth: 0.5))
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                }
            }
        }
    }

    private func isLedLit(blinkOn: Bool) -> Color {
        if flashActive { return led }
        if handshaking && blinkOn { return led }
        return Color(white: 0.45)
    }

    private func screen(glowActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.95)], startPoint: .top, endPoint: .bottom))
            .frame(width: 68, height: 46)
            .overlay(
                Rectangle()
                    .fill(Color(white: 0.08))
                    .frame(width: 60, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .fill(led.opacity(glowActive ? 1 : 0.2))
                            .frame(width: 26, height: 8),
                        alignment: .topTrailing
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(white: 0.3))
                            .frame(width: 26, height: 4)
                            .offset(y: -8),
                        alignment: .bottomLeading
                    ),
                alignment: .center
            )
    }
}