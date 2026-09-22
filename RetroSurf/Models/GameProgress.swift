import Foundation
import SwiftUI

@MainActor
final class GameProgress: ObservableObject {
    @Published var visitedSiteIDs: Set<String> = []
    @Published var currentTier: ModemTier = .v14_4
    @Published var flags: Set<String> = []

    /// The hidden achievement score (0…60). Persisted in the same
    /// UserDefaults store as the rest of the flag state — this is the
    /// numeric flag backing the achievements dashboard. It may ONLY change
    /// through `addScore(_:)`, never through `setFlag(_:)`.
    @Published private(set) var score = 0

    /// Fires the achievement event. `AchievementBroadcaster` posts to its
    /// observers from `addScore(_:)` exclusively.
    let achievements: AchievementBroadcaster = AchievementBroadcaster()

    private let catalog: SiteCatalog
    private let tierUpgradeThreshold = 2
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let currentTier = "GameProgress.currentTier"
        static let visitedSites = "GameProgress.visitedSites"
        static let flags = "GameProgress.flags"
        static let score = "GameProgress.score"
    }

    init(catalog: SiteCatalog) {
        self.catalog = catalog

        let savedTier = ModemTier(rawValue: defaults.integer(forKey: Keys.currentTier)) ?? .v14_4
        currentTier = savedTier

        if let data = defaults.data(forKey: Keys.visitedSites),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            visitedSiteIDs = Set(decoded)
        } else {
            visitedSiteIDs = []
        }

        if let data = defaults.data(forKey: Keys.flags),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            flags = Set(decoded)
        }

        score = max(0, defaults.integer(forKey: Keys.score))

        recomputeTier()
    }

    var visitedCount: Int { visitedSiteIDs.count }

    func isVisited(_ siteID: String) -> Bool {
        visitedSiteIDs.contains(siteID)
    }

    func isUnlocked(_ entry: SiteEntry) -> Bool {
        entry.requiredTier.rawValue <= currentTier.rawValue
    }

    func recordVisit(_ siteID: String) {
        guard let entry = catalog.entry(id: siteID), !entry.isUserAdded else { return }
        let isNew = visitedSiteIDs.insert(siteID).inserted
        saveVisits()
        if isNew {
            checkTierUpgrade()
        }
    }

    func setFlag(_ name: String) {
        guard flags.insert(name).inserted else { return }
        if let data = try? JSONEncoder().encode(Array(flags).sorted()) {
            defaults.set(data, forKey: Keys.flags)
        }
        defaults.synchronize()
    }

    private func checkTierUpgrade() {
        guard let next = ModemTier(rawValue: currentTier.rawValue + 1) else { return }
        guard tierVisitedCount >= tierUpgradeThreshold else { return }
        currentTier = next
        defaults.set(currentTier.rawValue, forKey: Keys.currentTier)
        checkTierUpgrade()
    }

    private func recomputeTier() {
        var tier: ModemTier = .v14_4
        while let next = ModemTier(rawValue: tier.rawValue + 1) {
            guard tierVisitedCount(at: tier) >= tierUpgradeThreshold else { break }
            tier = next
        }
        if tier != currentTier {
            currentTier = tier
            defaults.set(currentTier.rawValue, forKey: Keys.currentTier)
        }
    }

    private var tierVisitedCount: Int {
        tierVisitedCount(at: currentTier)
    }

    private func tierVisitedCount(at tier: ModemTier) -> Int {
        catalog.entries.filter { $0.requiredTier == tier && visitedSiteIDs.contains($0.id) }.count
    }

    private func saveVisits() {
        if let data = try? JSONEncoder().encode(Array(visitedSiteIDs).sorted()) {
            defaults.set(data, forKey: Keys.visitedSites)
        }
        defaults.synchronize()
    }

    /// Wipes all game progress (flags, score, visits, tier) back to a fresh
    /// state. Used by the debug progress reset; deliberately leaves the
    /// persistent snapshot of registered sites untouched.
    func resetProgress() {
        flags.removeAll()
        score = 0
        visitedSiteIDs.removeAll()
        currentTier = .v14_4
        defaults.removeObject(forKey: Keys.flags)
        defaults.removeObject(forKey: Keys.visitedSites)
        defaults.removeObject(forKey: Keys.score)
        defaults.removeObject(forKey: Keys.currentTier)
        defaults.synchronize()
    }
}

// MARK: - Part 2 · Achievement event layer

/// Announces achievement score events. `AchievementBroadcaster` posts to its
/// observers from `addScore(_:)` exclusively — never from flag changes.
@MainActor
final class AchievementBroadcaster {
    typealias ScoreHandler = (_ total: Int, _ delta: Int) -> Void
    private var handlers: [ScoreHandler] = []

    func observe(_ handler: @escaping ScoreHandler) {
        handlers.append(handler)
    }

    func broadcast(total: Int, delta: Int) {
        handlers.forEach { $0(total, delta) }
    }
}

/// The achievement score may change ONLY here (same-file extension — append-only,
/// no target surgery). Persists the total and announces the event to observers.
extension GameProgress {
    func addScore(_ points: Int) {
        guard points > 0 else { return }
        score += points
        defaults.set(score, forKey: Keys.score)
        defaults.synchronize()
        achievements.broadcast(total: score, delta: points)
    }
}
