import Foundation
import SwiftUI

struct Quest: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let targetSiteID: String
}

@MainActor
final class QuestManager: ObservableObject {
    @Published private(set) var completedQuestIDs: Set<String> = []

    static let allQuests: [Quest] = [
        Quest(
            id: "quest_pochta",
            title: "Заведи себе электронную почту",
            description: "Зарегистрируйся на pochta.su и получи свой первый email",
            targetSiteID: "pochta-su"
        )
    ]

    private enum Keys {
        static let completed = "QuestManager.completedQuestIDs"
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Keys.completed),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        completedQuestIDs = Set(decoded)
    }

    func quest(id: String) -> Quest? {
        Self.allQuests.first { $0.id == id }
    }

    func isCompleted(_ questID: String) -> Bool {
        completedQuestIDs.contains(questID)
    }

    func markCompleted(_ questID: String) {
        guard !completedQuestIDs.contains(questID) else { return }
        completedQuestIDs.insert(questID)
        persist()
    }

    func hasCompletedQuestFor(siteID: String) -> Bool {
        completedQuestIDs.contains { questID in
            Self.allQuests.first { $0.id == questID }?.targetSiteID == siteID
        }
    }

    func questID(forSiteID siteID: String) -> String? {
        Self.allQuests.first { $0.targetSiteID == siteID }?.id
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(completedQuestIDs).sorted()) {
            UserDefaults.standard.set(data, forKey: Keys.completed)
        }
        UserDefaults.standard.synchronize()
    }
}