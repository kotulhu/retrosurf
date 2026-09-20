import Foundation
import SwiftUI

@MainActor
final class GameProgress: ObservableObject {
    @Published var visitedSiteIDs: Set<String> = []
    @Published var currentTier: ModemTier = .v14_4

    private let catalog: SiteCatalog
    private let tierUpgradeThreshold = 2
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let currentTier = "GameProgress.currentTier"
        static let visitedSites = "GameProgress.visitedSites"
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
}