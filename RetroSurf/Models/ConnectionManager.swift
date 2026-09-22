import SwiftUI

/// Thrown by ConnectionManager.simulateLoad when the line dies mid-transfer.
/// The browser layer must abort the load, show a reconnect page, and never
/// partially render the page. The player may then retry the same request.
enum LoadInterruption: Error {
    case disconnected
}

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

    /// Base latency every page load pays regardless of size (seconds).
    /// Applied once at the start of each transfer by `simulateLoad`.
    var baseLatency: Double = 0.3

    /// Throughput profile the drifting line models around (bytes per second).
    var speedProfile: SpeedProfile = .dialUp

    /// Live line speed in bytes/second. Drifts every 3...7 seconds while the
    /// session is up; never outside `speedProfile.minBytesPerSec...maxBytesPerSec`.
    @Published private(set) var currentSpeed: Double = SpeedProfile.dialUp.minBytesPerSec

    /// The session's target speed, re-rolled by `reconnect()`. `currentSpeed`
    /// drifts slowly toward it; most connections land between min and avg.
    @Published private(set) var targetSpeed: Double = SpeedProfile.dialUp.minBytesPerSec

    /// Highest live speed reached during this session.
    @Published private(set) var sessionPeak: Double = SpeedProfile.dialUp.minBytesPerSec

    /// Lowest live speed reached during this session.
    @Published private(set) var sessionLow: Double = SpeedProfile.dialUp.minBytesPerSec
    private var heartbeatHandlers: [UUID: () -> Void] = [:]

    @available(*, deprecated, message: "Line speed is no longer constant. Use currentSpeed (live) or targetSpeed (session).")
    var speedBytesPerSecond: Double { currentSpeed }

    /// Adds work to the existing connected-session heartbeat. This avoids
    /// starting a separate timer for game systems such as message delivery.
    func addHeartbeatHandler(_ handler: @escaping () -> Void) {
        heartbeatHandlers[UUID()] = handler
    }

    /// Estimated wall time to transfer `bytes` at the current live speed:
    /// baseLatency + bytes / currentSpeed.
    func estimatedLoadTime(bytes: Int) -> TimeInterval {
        baseLatency + Double(max(bytes, 0)) / max(currentSpeed, 1)
    }

    /// Re-rolls the session target speed (mostly low-to-mid, rarely near max),
    /// resets the session peak/low to the current speed, then nudges
    /// `currentSpeed` toward the new target once. Normally called on connect
    /// and reconnect.
    func reconnect() {
        targetSpeed = Self.clamp(
            sampleTargetSpeed(),
            min: speedProfile.minBytesPerSec,
            max: speedProfile.maxBytesPerSec
        )
        sessionPeak = currentSpeed
        sessionLow = currentSpeed
        let baseDrift = (targetSpeed - currentSpeed) * 0.1
        currentSpeed = Self.clamp(currentSpeed + baseDrift,
                                  min: speedProfile.minBytesPerSec,
                                  max: speedProfile.maxBytesPerSec)
    }

    /// Samples a session target with a real-world distribution: most lines
    /// never get near 56k. [min, avg) 55%, ~avg±15% 30%, (avg, max] 10%, ~max 5%.
    private func sampleTargetSpeed() -> Double {
        let r = Double.random(in: 0..<1)
        let profile = speedProfile
        let value: Double
        if r < 0.55 {
            value = Double.random(in: profile.minBytesPerSec...profile.avgBytesPerSec)
        } else if r < 0.85 {
            value = profile.avgBytesPerSec * Double.random(in: 0.85...1.15)
        } else if r < 0.95 {
            value = Double.random(in: profile.avgBytesPerSec...profile.maxBytesPerSec)
        } else {
            value = profile.maxBytesPerSec * Double.random(in: 0.95...1.0)
        }
        return Self.clamp(value, min: profile.minBytesPerSec, max: profile.maxBytesPerSec)
    }

    /// Simulates the transfer of `bytes` bytes at line speed.
    ///
    /// Contract for the browser layer (the only caller):
    ///  - Must only be invoked while `isConnected`; otherwise it throws
    ///    `LoadInterruption.disconnected` immediately.
    ///  - `bytes == 0` returns immediately with no side effects.
    ///  - May throw `LoadInterruption.disconnected` at ANY point mid-transfer
    ///    (line noise, hang-up, random drop). The caller must then abort the
    ///    load, show a reconnect page, and never partially render the page.
    ///    The player is allowed to retry the same request.
    ///  - Throws `CancellationError` when the surrounding task is cancelled.
    ///  - `progress` reports 0...1 as the transfer advances (optional).
    ///  - The transfer slices into ~500 ms chunks and re-reads `currentSpeed`
    ///    every slice, so loads visibly slow down and speed up as the line
    ///    drifts. Elapsed time approximates sum(sliceBytes / currentSpeed),
    ///    plus `baseLatency` once at the start.
    ///  - Sites themselves never sleep: this helper lives exclusively in the
    ///    browser layer, never inside a site's handle(_:).
    func simulateLoad(bytes: Int, progress: ((Double) -> Void)? = nil) async throws {
        guard isConnected else { throw LoadInterruption.disconnected }
        let totalBytes = max(bytes, 0)
        if totalBytes == 0 { return }

        if baseLatency > 0 {
            try? await Task.sleep(nanoseconds: UInt64(baseLatency * 1_000_000_000))
        }
        guard isConnected, !Task.isCancelled else { throw LoadInterruption.disconnected }

        signalReceive(bytes: totalBytes)
        let sliceSeconds: TimeInterval = 0.5
        let dropAt: Double? = (Double.random(in: 0..<100) < 8 && totalBytes >= 256)
            ? Double.random(in: 0.3...0.9)
            : nil
        var transferred = 0.0
        while transferred < Double(totalBytes) {
            if Task.isCancelled { throw CancellationError() }
            guard isConnected else { throw LoadInterruption.disconnected }
            if let dropAt, transferred >= Double(totalBytes) * dropAt {
                throw LoadInterruption.disconnected
            }
            let sliceBytes = currentSpeed * sliceSeconds
            transferred += sliceBytes
            try await Task.sleep(nanoseconds: UInt64(sliceSeconds * 1_000_000_000))
            progress?(max(0, min(1, transferred / Double(totalBytes))))
        }
    }

    private var lastFakeError: FakeConnectionError?

#if DEBUG
    /// Connection-phase transitions, proxied into the shared DebugLogger.
    var debugLog: [String] {
        DebugLogger.shared.entries.filter { $0.contains("[Connection]") }
    }
#endif

    private let audio = ModemHandshakeAudio()
    private var connectTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var idleMonitorTask: Task<Void, Never>?
    private var packetTask: Task<Void, Never>?
    private var trafficPulseTask: Task<Void, Never>?
    private var errorRecoveryTask: Task<Void, Never>?
    private var driftTask: Task<Void, Never>?

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
        stopDrift()
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
            self.startDrift()
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
        DebugLogger.shared.log("Connection", "\(from) → \(Self.describe(newState))    [\(source)]")
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
        stopDrift()
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
        stopDrift()
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
        stopDrift()
        connectTask = nil
        disconnectTask = nil
        idleMonitorTask = nil
        packetTask = nil
        trafficPulseTask = nil
        errorRecoveryTask = nil
    }

    // MARK: - Live speed drift

    /// Starts (once) the session-long speed drift. The loop ticks at random
    /// 3...7 second intervals and keeps publishing new `currentSpeed` values
    /// even while nothing is loading. Cancelled cleanly by `stopDrift()`.
    private func startDrift() {
        guard driftTask == nil else { return }
        driftTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let interval = Double.random(in: 3...7)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, self.isConnected else { return }
                self.tickDrift()
            }
        }
    }

    private func stopDrift() {
        driftTask?.cancel()
        driftTask = nil
    }

    /// One drift tick: pull `currentSpeed` 10% toward the session target, add
    /// ±8% jitter, and with 1-in-20 odds apply a line spike. Guards: the value
    /// never moves more than ~35% in a single tick and always stays inside the
    /// profile bounds. Peak/low are updated every tick.
    private func tickDrift() {
        let profile = speedProfile
        let baseDrift = (targetSpeed - currentSpeed) * 0.1
        let jitter = currentSpeed * Double.random(in: -0.08...0.08)
        var next = currentSpeed + baseDrift + jitter
        if Int.random(in: 0..<20) == 0 {
            next *= Double.random(in: 0.75...1.25)
        }
        let maxJump = max(currentSpeed * 0.35, 1)
        next = min(next, currentSpeed + maxJump)
        next = max(next, currentSpeed - maxJump)
        currentSpeed = Self.clamp(next, min: profile.minBytesPerSec, max: profile.maxBytesPerSec)
        sessionPeak = max(sessionPeak, currentSpeed)
        sessionLow = min(sessionLow, currentSpeed)
        heartbeatHandlers.values.forEach { $0() }
    }

    deinit {
        driftTask?.cancel()
    }
}

private extension ConnectionManager {
    static func clamp(_ value: Double, min low: Double, max high: Double) -> Double {
        Swift.max(low, Swift.min(high, value))
    }
}
