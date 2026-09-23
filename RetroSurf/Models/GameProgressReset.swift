import Foundation

extension Notification.Name {
    static let gameProgressDidReset = Notification.Name("RetroSurf.gameProgressDidReset")
}

/// Resets every piece of gameplay state back to a fresh start. App settings
/// (skin, modem speed) and bundled Resources/sites are left untouched.
@MainActor
enum GameProgressReset {
    static func perform(
        game: GameProgress,
        quests: QuestManager,
        clock: GameClock,
        scheduler: MessageScheduler,
        sites: SiteSession,
        catalog: SiteCatalog,
        questGenerator: QuestGenerator,
        fileQuestTracker: FileQuestTracker
    ) {
        game.resetProgress()
        quests.resetCompleted()
        clock.reset()
        clock.start()
        scheduler.clearAll()
        questGenerator.clearSenderCache()
        sites.registry.removeUserCreatedStaticSites()
        sites.resetAllGameplay()
        catalog.resetUserCreatedContent()
        fileQuestTracker.reset()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "homepageFeedbackCount")
        for index in 1...3 {
            defaults.removeObject(forKey: "homepage.feedback.\(index)")
        }
        defaults.removeObject(forKey: "MailboxManager.messages")
        defaults.synchronize()

        NotificationCenter.default.post(name: .gameProgressDidReset, object: nil)
    }
}
