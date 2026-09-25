import Foundation

/// In-memory session statistics for the «последняя страница интернета»:
/// session duration, MB transferred up the line, MB downloaded. Nothing is
/// persisted; a fresh launch starts a fresh session.
@MainActor
final class SessionStats: ObservableObject {
    private let bus: GameBus
    private var subscriptionID: UUID?

    let startedAt: Date

    /// Bytes the player sent up the line (mail uploads, forum posts).
    @Published private(set) var bytesTransferred = 0
    /// Bytes received by completed file downloads.
    @Published private(set) var bytesDownloaded = 0

    init(bus: GameBus) {
        self.bus = bus
        self.startedAt = Date()
        subscriptionID = bus.subscribe { [weak self] event in
            self?.handle(event)
        }
    }

    deinit {
        if let id = subscriptionID {
            Task { @MainActor [bus] in
                bus.unsubscribe(id)
            }
        }
    }

    private func handle(_ event: GameBus.Event) {
        switch event {
        case .bytesTransferred(let payload):
            bytesTransferred += max(payload.bytes, 0)
        case .bytesDownloaded(let payload):
            bytesDownloaded += max(payload.bytes, 0)
        default:
            break
        }
    }

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// "13 сек", "4 мин", "1 ч 12 мин".
    var elapsedFormatted: String {
        let total = Int(elapsed)
        if total < 60 {
            return "\(total) сек"
        }
        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes) мин"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return "\(hours) ч \(rest) мин"
    }

    /// Megabiytes (1024²) transferred up the line, from raw byte counts.
    var megabytesTransferred: Double {
        Double(max(bytesTransferred, 0)) / (1024 * 1024)
    }

    var megabytesDownloaded: Double {
        Double(max(bytesDownloaded, 0)) / (1024 * 1024)
    }

    func formatted(_ megabytes: Double) -> String {
        String(format: "%.1f", megabytes).replacingOccurrences(of: ",", with: ".")
    }
}