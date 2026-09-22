import Combine
import Foundation

/// Minimal in-game clock. Persists the current in-game date and advances it
/// one day per `realSecondsPerDay` of wall time — a debug-visible heartbeat
/// rather than a full calendar simulation. Debug panel and quest system can
/// read `inGameDate`; reset returns it to the 1999 starting date.
@MainActor
final class GameClock: ObservableObject {
    @Published private(set) var inGameDate: Date

    private let defaults = UserDefaults.standard
    private var advanceTask: Task<Void, Never>?
    private let realSecondsPerDay: TimeInterval
    private var lastWallDate: Date

    private enum Keys {
        static let inGameDate = "GameClock.inGameDate"
        static let lastWallDate = "GameClock.lastWallDate"
    }

    init(realSecondsPerDay: TimeInterval = 30) {
        self.realSecondsPerDay = realSecondsPerDay
        let start = Self.startDate
        if let raw = defaults.data(forKey: Keys.inGameDate),
           let saved = try? JSONDecoder().decode(Date.self, from: raw) {
            inGameDate = saved
        } else {
            inGameDate = start
            if let data = try? JSONEncoder().encode(start) {
                defaults.set(data, forKey: Keys.inGameDate)
            }
        }
        if defaults.object(forKey: Keys.lastWallDate) == nil {
            defaults.set(Date(), forKey: Keys.lastWallDate)
        }
        lastWallDate = (defaults.object(forKey: Keys.lastWallDate) as? Date) ?? Date()
        defaults.synchronize()
    }

    /// The in-game epoch: midnight, 1 January 1999, Kyiv/Moscow-era start date
    /// of the "Российский Интернет" fantasy.
    static var startDate: Date {
        let components = DateComponents(year: 1999, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 915_148_800)
    }

    /// Starts the advance loop. Called by the app once; idempotent.
    func start() {
        guard advanceTask == nil else { return }
        advanceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    /// One-second heartbeat: catch up wall-time that passed while off, then
    /// advance by whole game-days only.
    private func tick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastWallDate)
        guard elapsed >= realSecondsPerDay else { return }
        let wholeDays = Int(elapsed / realSecondsPerDay)
        guard wholeDays > 0 else { return }
        lastWallDate = now
        defaults.set(now, forKey: Keys.lastWallDate)
        advance(byDays: wholeDays)
    }

    private func advance(byDays days: Int) {
        let calendar = Calendar(identifier: .gregorian)
        inGameDate = calendar.date(byAdding: .day, value: days, to: inGameDate) ?? inGameDate
        if let data = try? JSONEncoder().encode(inGameDate) {
            defaults.set(data, forKey: Keys.inGameDate)
        }
        defaults.synchronize()
#if DEBUG
        DebugLogger.shared.log("Clock", "inGameDate: \(Self.format(inGameDate))")
#endif
    }

    /// Reset the clock to the epoch starting date (used by progress reset).
    func reset() {
        advanceTask?.cancel()
        advanceTask = nil
        inGameDate = Self.startDate
        lastWallDate = Date()
        defaults.set(Date(), forKey: Keys.lastWallDate)
        if let data = try? JSONEncoder().encode(inGameDate) {
            defaults.set(data, forKey: Keys.inGameDate)
        }
        defaults.synchronize()
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }
}