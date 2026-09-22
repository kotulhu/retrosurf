import SwiftUI

@MainActor
enum InteractiveExperienceRegistry {
    static let pochtaInboxExperienceID = "pochta-inbox"

    @ViewBuilder
    static func view(
        for info: QuestExperienceInfo,
        quests: QuestManager,
        sites: SiteSession,
        onBack: @escaping () -> Void,
        onOpenSite: @escaping (String) -> Void
    ) -> some View {
        switch info.experienceID {
        case Self.pochtaInboxExperienceID:
            PochtaInboxExperience(siteID: info.siteID, onBack: onBack, onOpenSite: onOpenSite)
        case "pochta-registration":
            if quests.isCompleted(QuestManager.registrationQuestID) {
                PochtaInboxExperience(siteID: info.siteID, onBack: onBack, onOpenSite: onOpenSite)
            } else {
                QuestExperienceView(info: info, onBack: onBack)
            }
        default:
            QuestExperienceView(info: info, onBack: onBack)
        }
    }
}
