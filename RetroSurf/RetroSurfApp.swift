import SwiftUI

@main
struct RetroSurfApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var connection: ConnectionManager
    @StateObject private var dialUp: DialUpPanelController
    @StateObject private var catalog: SiteCatalog
    @StateObject private var game: GameProgress
    @StateObject private var mailbox: MailboxManager
    @StateObject private var quests: QuestManager
    @StateObject private var sites: SiteSession

    init() {
        let connection = ConnectionManager()
        let catalog = SiteCatalog()
        let mailbox = MailboxManager()
        let registry = SiteRegistry()
        let mailSite = MailSite()
        registry.register(mailSite)
        let session = SiteSession(registry: registry)
        if let raw = UserDefaults.standard.dictionary(forKey: SiteSession.snapshotsDefaultsKey) as? [String: Data] {
            try? session.restoreAll(from: raw)
        }
        _settings = StateObject(wrappedValue: AppSettings())
        _connection = StateObject(wrappedValue: connection)
        _dialUp = StateObject(wrappedValue: DialUpPanelController(connection: connection))
        _catalog = StateObject(wrappedValue: catalog)
        _game = StateObject(wrappedValue: GameProgress(catalog: catalog))
        _mailbox = StateObject(wrappedValue: mailbox)
        _quests = StateObject(wrappedValue: QuestManager(mailbox: mailbox))
        _sites = StateObject(wrappedValue: session)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(connection)
                .environmentObject(dialUp)
                .environmentObject(catalog)
                .environmentObject(game)
                .environmentObject(mailbox)
                .environmentObject(quests)
                .environmentObject(sites)
                .navigationTitle("RetroSurf")
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}