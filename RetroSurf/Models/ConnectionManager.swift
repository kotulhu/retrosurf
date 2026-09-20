import SwiftUI

enum FakeConnectionError: CaseIterable {
    case lineIsBusy
    case noDialTone
    case noCarrier
    case serverNotResponding
    case authenticationTimeout
    case lineNoise

    var displayText: String {
        switch self {
        case .lineIsBusy: return "Линия занята. Повторный дозвон через 10 секунд..."
        case .noDialTone: return "Нет гудка. Проверьте телефонный кабель."
        case .noCarrier: return "Не удалось установить несущую частоту."
        case .serverNotResponding: return "Сервер провайдера не отвечает."
        case .authenticationTimeout: return "Превышено время ожидания авторизации."
        case .lineNoise: return "Обрыв соединения из-за помех на линии."
        }
    }
}

enum ConnectionPhase: Equatable {
    case idle
    case dialing
    case waitingForCarrier
    case handshaking
    case verifyingIdentity
    case assigningAddress
    case connected(speed: Int)
    case disconnecting
    case error(String)

    var statusText: String {
        switch self {
        case .idle: return "Не подключено"
        case .dialing: return "Набор номера…"
        case .waitingForCarrier: return "Ожидание сигнала…"
        case .handshaking: return "Согласование протокола связи…"
        case .verifyingIdentity: return "Проверка имени пользователя и пароля…"
        case .assigningAddress: return "Регистрация в сети…"
        case .connected: return "Подключено к автоответчику"
        case .disconnecting: return "Разрыв соединения…"
        case .error(let message): return message
        }
    }
}

@MainActor
final class ConnectionManager: ObservableObject {
    @Published var state: ConnectionPhase = .idle
    @Published var bytesSent = 0
    @Published var bytesReceived = 0
    @Published var errorCount = 0
    @Published var isTransmitting = false
    @Published var txFlash = false
    @Published var rxFlash = false

    var maximumSpeed: Int = 56_000
    private(set) var isSessionActive = false

    private var lastFakeError: FakeConnectionError?

#if DEBUG
    @Published var debugLog: [String] = []
#endif

    private let audio = ModemHandshakeAudio()
    private var connectTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var idleMonitorTask: Task<Void, Never>?
    private var packetTask: Task<Void, Never>?
    private var trafficPulseTask: Task<Void, Never>?
    private var errorRecoveryTask: Task<Void, Never>?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var isHandshaking: Bool {
        if case .handshaking = state { return true }
        return false
    }

    func connect(maximumSpeed: Int? = nil) {
        if let maximumSpeed { self.maximumSpeed = maximumSpeed }
        guard !isConnectingOpen else { return }
        startSession()
    }

    func disconnect() {
        errorRecoveryTask?.cancel()
        audio.stop()
        guard isSessionActive else { return }
        transition(to: .disconnecting, source: "разрыв по кнопке")
        disconnectTask?.cancel()
        disconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.5...1.5) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.endSession()
        }
    }

    func reportTraffic(sent: Int, received: Int) {
        guard isConnected else { return }
        if sent > 0 { signalTransmit(bytes: sent) }
        if received > 0 { signalReceive(bytes: received) }
        isTransmitting = true
        trafficPulseTask?.cancel()
        trafficPulseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            self.isTransmitting = false
        }
    }

    func signalTransmit(bytes: Int) {
        bytesSent += max(bytes, 0)
        flashIndicator(\.txFlash)
    }

    func signalReceive(bytes: Int) {
        bytesReceived += max(bytes, 0)
        flashIndicator(\.rxFlash)
    }

    private func flashIndicator(_ keyPath: ReferenceWritableKeyPath<ConnectionManager, Bool>) {
        self[keyPath: keyPath] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                self?[keyPath: keyPath] = false
            }
        }
    }

    private var isConnectingOpen: Bool {
        switch state {
        case .idle, .error: return false
        case .dialing, .waitingForCarrier, .handshaking, .verifyingIdentity,
             .assigningAddress, .connected, .disconnecting: return true
        }
    }

    private func startSession() {
        cancelSessionTasks()
        isSessionActive = true
        bytesSent = 0
        bytesReceived = 0
        errorCount = 0
        isTransmitting = false
        txFlash = false
        rxFlash = false

        connectTask = Task { [weak self] in
            guard let self else { return }
            for stage: ConnectionPhase in [.dialing, .waitingForCarrier] {
                self.transition(to: stage, source: "дозвон")
                await self.stageDelay()
                guard !Task.isCancelled else { return }
            }
            self.transition(to: .handshaking, source: "дозвон")
            self.audio.play()
            let handshakeDuration = max(self.audio.duration, 3)
            await self.stageDelay(seconds: handshakeDuration...(handshakeDuration + 0.8))
            guard !Task.isCancelled else { return }
            self.audio.stop()
            self.transition(to: .verifyingIdentity, source: "дозвон")
            await self.stageDelay()
            guard !Task.isCancelled else { return }
            self.transition(to: .assigningAddress, source: "дозвон")
            await self.stageDelay()
            guard !Task.isCancelled else { return }
            self.transition(to: .connected(speed: self.negotiatedSpeed()), source: "дозвон")
            self.startIdleMonitor()
            self.startPacketSimulation()
        }
    }

    private func stageDelay(seconds: ClosedRange<Double> = 0.5...2) async {
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: seconds) * 1_000_000_000))
    }

    private func negotiatedSpeed() -> Int {
        let factor = Double.random(in: 0.80...0.93)
        let raw = Double(maximumSpeed) * factor
        return Int((raw / 100).rounded()) * 100
    }

    private func transition(to newState: ConnectionPhase, source: String) {
        let from = Self.describe(state)
        state = newState
#if DEBUG
        logTransition("\(from) → \(Self.describe(newState))    [\(source)]")
#endif
    }

    private static func describe(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .dialing: return "dialing"
        case .waitingForCarrier: return "waitingForCarrier"
        case .handshaking: return "handshaking"
        case .verifyingIdentity: return "verifyingIdentity"
        case .assigningAddress: return "assigningAddress"
        case .connected(let speed): return "connected(\(speed))"
        case .disconnecting: return "disconnecting"
        case .error(let message): return "error(\(message))"
        }
    }

    private func nextFakeError() -> FakeConnectionError {
        let candidates = FakeConnectionError.allCases.filter { $0 != lastFakeError }
        let picked = candidates.randomElement() ?? .lineIsBusy
        lastFakeError = picked
        return picked
    }

#if DEBUG
    private func logTransition(_ description: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        debugLog.append("[\(timestamp)] \(description)")
        if debugLog.count > 200 { debugLog.removeFirst() }
    }
#endif

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        idleMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 10...20) * 1_000_000_000))
                guard !Task.isCancelled, self.isConnected else { return }
                if Double.random(in: 0...100) < 8 {
                    self.dropConnection()
                }
            }
        }
    }

    private func startPacketSimulation() {
        packetTask?.cancel()
        packetTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.1...0.6) * 1_000_000_000))
                guard !Task.isCancelled, self.isConnected else { return }
                self.simulatePacketActivity()
            }
        }
    }

    private func simulatePacketActivity() {
        if Double.random(in: 0...100) < 70 {
            signalReceive(bytes: Int.random(in: 100...1_500))
        } else {
            signalTransmit(bytes: Int.random(in: 40...200))
        }
    }

    private func dropConnection() {
        audio.stop()
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
        packetTask?.cancel()
        packetTask = nil
        isTransmitting = false
        errorCount += 1
        let error = nextFakeError()
        transition(to: .error(error.displayText), source: "случайный обрыв")
        errorRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.endSession()
        }
    }

    private func endSession() {
        audio.stop()
        cancelSessionTasks()
        isSessionActive = false
        isTransmitting = false
        txFlash = false
        rxFlash = false
        bytesSent = 0
        bytesReceived = 0
        errorCount = 0
        transition(to: .idle, source: "завершение сессии")
    }

    private func cancelSessionTasks() {
        connectTask?.cancel()
        disconnectTask?.cancel()
        idleMonitorTask?.cancel()
        packetTask?.cancel()
        trafficPulseTask?.cancel()
        errorRecoveryTask?.cancel()
        connectTask = nil
        disconnectTask = nil
        idleMonitorTask = nil
        packetTask = nil
        trafficPulseTask = nil
        errorRecoveryTask = nil
    }
}