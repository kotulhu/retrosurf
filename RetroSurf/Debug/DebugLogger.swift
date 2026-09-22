import Combine
import Foundation

#if DEBUG
/// Single in-memory debug log shared across game systems. Lives only in
/// DEBUG builds; Release never compiles it. Keeps a bounded tail so the log
/// cannot grow unbounded during long sessions.
@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var entries: [String] = []

    /// Hard cap: oldest entries are dropped past this.
    private let capacity = 500

    func log(_ category: String, _ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        entries.append("[\(ts)] [\(category)] \(message)")
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Reset log contents (used by the progress reset for visibility).
    func clear() {
        entries.removeAll()
    }
}
#endif