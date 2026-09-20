import SwiftUI

@main
struct RetroSurfApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var connection: ConnectionManager
    @StateObject private var dialUp: DialUpPanelController
    @StateObject private var catalog: SiteCatalog
    @StateObject private var game: GameProgress
    @StateObject private var quests: QuestManager

    init() {
        let connection = ConnectionManager()
        let catalog = SiteCatalog()
        _settings = StateObject(wrappedValue: AppSettings())
        _connection = StateObject(wrappedValue: connection)
        _dialUp = StateObject(wrappedValue: DialUpPanelController(connection: connection))
        _catalog = StateObject(wrappedValue: catalog)
        _game = StateObject(wrappedValue: GameProgress(catalog: catalog))
        _quests = StateObject(wrappedValue: QuestManager())
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
                .navigationTitle("RetroSurf")
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}