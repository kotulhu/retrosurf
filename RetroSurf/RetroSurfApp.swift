import SwiftUI

@main
struct RetroSurfApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var connection: ConnectionManager
    @StateObject private var dialUp: DialUpPanelController
    @StateObject private var catalog: SiteCatalog
    @StateObject private var game: GameProgress
    @StateObject private var quests: QuestManager
    @StateObject private var sites: SiteSession
    @StateObject private var questGenerator: QuestGenerator
    @StateObject private var scheduler: MessageScheduler
    @StateObject private var clock: GameClock

    init() {
        let connection = ConnectionManager()
        let catalog = SiteCatalog()
        let registry = SiteRegistry()
        let mailSite = MailSite()
        let messageScheduler = MessageScheduler()
        registry.register(mailSite)
        let homepageSite = HomepageSite(mailSite: mailSite, messageScheduler: messageScheduler)
        registry.register(homepageSite)
        let session = SiteSession(registry: registry)
        let senders = SenderCatalog.loadFromBundle()
        let questManager = QuestManager(mailSite: mailSite, messageScheduler: messageScheduler)
        _quests = StateObject(wrappedValue: questManager)
        let generator = QuestGenerator(
            quests: QuestGenerator.loadQuestsFromBundle(),
            senders: senders,
            registry: registry,
            messageScheduler: messageScheduler
        )
        connection.addHeartbeatHandler { [weak generator] in
            generator?.processDueDeliveries()
        }
        mailSite.onHomepageFeedbackReceived = { [weak homepageSite] in
            guard let homepageSite, homepageSite.recordFeedback() else { return }
            questManager.markCompleted(QuestManager.homepageQuestID)
        }
        generator.processDueDeliveries()
        let gameClock = GameClock()
        gameClock.start()
        if let raw = UserDefaults.standard.dictionary(forKey: SiteSession.snapshotsDefaultsKey) as? [String: Data] {
            try? session.restoreAll(from: raw)
        }
        _settings = StateObject(wrappedValue: AppSettings())
        _connection = StateObject(wrappedValue: connection)
        _dialUp = StateObject(wrappedValue: DialUpPanelController(connection: connection))
        _catalog = StateObject(wrappedValue: catalog)
        _game = StateObject(wrappedValue: GameProgress(catalog: catalog))
        _sites = StateObject(wrappedValue: session)
        _questGenerator = StateObject(wrappedValue: generator)
        _scheduler = StateObject(wrappedValue: messageScheduler)
        _clock = StateObject(wrappedValue: gameClock)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(connection)
                .environmentObject(dialUp)
                .environmentObject(catalog)
                .environmentObject(game)
                .environmentObject(quests)
                .environmentObject(sites)
                .environmentObject(questGenerator)
                .environmentObject(scheduler)
                .environmentObject(clock)
                .navigationTitle("RetroSurf")
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
#if DEBUG
        .commands {
            CommandMenu("Debug") {
                Button("Панель отладки…") { openWindow(id: "debug") }
                    .keyboardShortcut("D", modifiers: [.command, .shift])
            }
        }
#endif
#if DEBUG
        Window("Отладка", id: "debug") {
            DebugPanelView()
                .environmentObject(settings)
                .environmentObject(catalog)
                .environmentObject(game)
                .environmentObject(quests)
                .environmentObject(sites)
                .environmentObject(questGenerator)
                .environmentObject(scheduler)
                .environmentObject(clock)
        }
        .defaultSize(width: 760, height: 560)
#endif
    }

    @Environment(\.openWindow) private var openWindow
}
