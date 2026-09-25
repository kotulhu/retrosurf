import Foundation

/// Запись в гостевой книге фан-клуба. Записи из content.json (seed) никогда
/// не сохраняются — timestamp считается при рендере из daysAgo. В state
/// живут только записи, оставленные игроком.
struct GuestbookEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let author: String
    let email: String
    let text: String
    let timestamp: Date
}

struct FanClubState: Codable, Sendable {
    var playerEntries: [GuestbookEntry] = []
    /// Счётчик id для новых записей игрока (seed-id имеют префикс "gb" и
    /// в счётчик не входят — коллизии невозможны).
    var nextEntryId: Int = 1
}
