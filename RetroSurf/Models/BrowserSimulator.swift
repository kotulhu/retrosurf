import SwiftUI

@MainActor
final class BrowserSimulator: ObservableObject {
    @Published private(set) var statusText = "Готово."
    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published private(set) var connectionBlocked = false

    weak var connection: ConnectionManager?

    private var timer: Timer?
    private var loadCompletion: (() -> Void)?
    private static let simulatedPageSize = 7_000

    @discardableResult
    func go(to input: String, completion: (() -> Void)? = nil) -> Bool {
        startLoading(initialText: "Загрузка \(input)…", completion: completion)
    }

    @discardableResult
    func reload(completion: (() -> Void)? = nil) -> Bool {
        startLoading(initialText: "Перезагрузка страницы…", completion: completion)
    }

    @discardableResult
    func home(completion: (() -> Void)? = nil) -> Bool {
        startLoading(initialText: "Открываю домашнюю страницу…", completion: completion)
    }

    func acknowledgeBlocked() {
        connectionBlocked = false
    }

    func requestBlocked() {
        statusText = "Нет соединения."
        connectionBlocked = true
    }

    func stop() {
        loadCompletion = nil
        finishLoading()
        statusText = "Остановлено."
    }

    func cancelLoad() {
        loadCompletion = nil
        timer?.invalidate()
        timer = nil
        isLoading = false
    }

    func notifyUnavailable(_ action: String) {
        cancelLoad()
        statusText = "«\(action)» недоступно в этой сборке."
    }

    private func startLoading(initialText: String, completion: (() -> Void)? = nil) -> Bool {
        guard connection?.isConnected == true else {
            connectionBlocked = true
            statusText = "Нет соединения."
            return false
        }
        timer?.invalidate()
        loadCompletion = nil
        isLoading = true
        progress = 0
        statusText = initialText
        loadCompletion = completion
        connection?.reportTraffic(sent: 160 + initialText.count, received: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        return true
    }

    private func tick() {
        let delta = Double.random(in: 0.05...0.12)
        progress += delta
        connection?.reportTraffic(sent: 0, received: Int(delta * Double(Self.simulatedPageSize)))
        switch progress {
        case 0.0..<0.25:
            statusText = "Подключение к модему…"
        case 0.25..<0.55:
            statusText = "Отправка запроса…"
        case 0.55..<0.95:
            statusText = "Получение данных…"
        default:
            finishLoading()
            statusText = "Готово."
        }
    }

    private func finishLoading() {
        timer?.invalidate()
        timer = nil
        isLoading = false
        let completion = loadCompletion
        loadCompletion = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isLoading else { return }
                self.progress = 0
            }
        }
        completion?()
    }

    deinit {
        timer?.invalidate()
    }
}