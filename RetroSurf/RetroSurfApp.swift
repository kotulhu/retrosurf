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
    @StateObject private var ambientGenerator: AmbientMailGenerator
    @StateObject private var npcMessenger: NpcMessenger
    @StateObject private var playerPageState: PlayerPageState
    private let playerPageInstaller: PlayerPageInstaller
    private let finalSiteInstaller: FinalSiteInstaller
    @StateObject private var downloads: DownloadsStore
    @StateObject private var saveDialog: RetroSaveDialogController
    @StateObject private var fileQuestTracker: FileQuestTracker
    @StateObject private var loveQuestTracker: LoveQuestTracker
    @StateObject private var webmasterQuestTracker: WebmasterQuestTracker
    @StateObject private var progressStore: ProgressStore
    @StateObject private var sessionStats: SessionStats
    private let mailSite: MailSite
    private let fileStore: FileStore
    private let localFileStore: LocalFileStore
    private let bus: GameBus

    init() {
        let connection = ConnectionManager()
        let catalog = SiteCatalog()
        let registry = SiteRegistry()
        let bus = GameBus()
        let fileStore = FileStore(bus: bus)
        // Pre-installed files land in "Мои документы" once; nothing is
        // downloaded, no events are fired.
        PreinstalledFilesInstaller.install(
            catalog: PreinstalledFilesCatalog.loadFromBundle(),
            fileStore: fileStore
        )
        let localFileStore = LocalFileStore(fileStore: fileStore, bus: bus)
        let downloadsStore = DownloadsStore(fileStore: fileStore, localFileStore: localFileStore, bus: bus)
        // После восстановления графа файлов убедимся, что у каждого ранее
        // скачанного файла на диске снова есть текстовая заглушка (п. «всё,
        // что попадает в загрузки, должно оставаться и в файловой системе»).
        downloadsStore.ensureStubFiles()
        let messageScheduler = MessageScheduler()
        let ambientCatalog = AmbientCatalog.loadFromBundle()
        let npcCatalog = NpcCatalog.loadFromBundle()
        let mailSite = MailSite(fileStore: fileStore, localFileStore: localFileStore, bus: bus, npcCatalog: npcCatalog)
        let ambientGenerator = AmbientMailGenerator(
            catalog: ambientCatalog,
            mailSite: mailSite
        )
        let npcMessenger = NpcMessenger(
            catalog: npcCatalog,
            mailSite: mailSite
        )
        registry.register(mailSite)
        let homepageSite = HomepageSite(mailSite: mailSite, messageScheduler: messageScheduler)
        registry.register(homepageSite)
        let filesSite = FilesSite(catalog: FilesCatalog.loadFromBundle())
        registry.register(filesSite)
        let fanClubSite = FanClubSite(content: FanClubContent.loadFromBundle())
        registry.register(fanClubSite)
        let melodiaSite = MelodiaSite(
            catalog: FilesCatalog.loadFromBundle(basePath: "sites/melodia.su"),
            bulkLoader: FilesBulkLoader.loadFromBundle(basePath: "sites/melodia.su/generated")
        )
        registry.register(melodiaSite)
        let loveSite = LoveSite(
            content: LoveContent.loadFromBundle(),
            fileStore: fileStore,
            localFileStore: localFileStore,
            bus: bus
        )
        registry.register(loveSite)
        StaticSiteLoader.loadFromBundle(registerTo: registry)
        let playerPageState = PlayerPageState()
        let playerPageInstaller = PlayerPageInstaller(
            registry: registry,
            mailSite: mailSite,
            state: playerPageState,
            bus: bus
        )
        let session = SiteSession(registry: registry)
        let senders = SenderCatalog.loadFromBundle()
        let questManager = QuestManager(messageScheduler: messageScheduler, ambientGenerator: ambientGenerator)
        _quests = StateObject(wrappedValue: questManager)
        let game = GameProgress(catalog: catalog)
        let flags = GameProgressFlagStore(game: game, bus: bus)
        let fileQuestTracker = FileQuestTracker(
            quests: FileQuestCatalog.loadFromBundle().quests,
            mailSite: mailSite,
            npcCatalog: npcCatalog,
            flags: flags,
            bus: bus,
            fileStore: fileStore
        )
        let generator = QuestGenerator(
            quests: QuestGenerator.loadQuestsFromBundle(),
            senders: senders,
            registry: registry,
            messageScheduler: messageScheduler
        )
        let loveQuestTracker = LoveQuestTracker(
            content: LoveContent.loadFromBundle(),
            replies: LoveRepliesCatalog.loadFromBundle(),
            loveSite: loveSite,
            mailSite: mailSite,
            flags: flags,
            bus: bus
        )
        let webmasterQuestTracker = WebmasterQuestTracker(
            npcCatalog: npcCatalog,
            mailSite: mailSite,
            flags: flags,
            bus: bus
        )
        let progressStore = ProgressStore(bus: bus)
        let sessionStats = SessionStats(bus: bus)
        let finalSiteInstaller = FinalSiteInstaller(
            progress: progressStore,
            registry: registry,
            stats: sessionStats
        )
        connection.addHeartbeatHandler { [weak generator] in
            generator?.processDueDeliveries()
        }
        connection.addHeartbeatHandler { [weak fileQuestTracker] in
            fileQuestTracker?.tickOnce()
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
        _game = StateObject(wrappedValue: game)
        _sites = StateObject(wrappedValue: session)
        _questGenerator = StateObject(wrappedValue: generator)
        _scheduler = StateObject(wrappedValue: messageScheduler)
        _clock = StateObject(wrappedValue: gameClock)
        _ambientGenerator = StateObject(wrappedValue: ambientGenerator)
        _npcMessenger = StateObject(wrappedValue: npcMessenger)
        _playerPageState = StateObject(wrappedValue: playerPageState)
        self.playerPageInstaller = playerPageInstaller
        _downloads = StateObject(wrappedValue: downloadsStore)
        _saveDialog = StateObject(wrappedValue: RetroSaveDialogController())
        _fileQuestTracker = StateObject(wrappedValue: fileQuestTracker)
        _loveQuestTracker = StateObject(wrappedValue: loveQuestTracker)
        _webmasterQuestTracker = StateObject(wrappedValue: webmasterQuestTracker)
        _progressStore = StateObject(wrappedValue: progressStore)
        _sessionStats = StateObject(wrappedValue: sessionStats)
        self.mailSite = mailSite
        self.fileStore = fileStore
        self.localFileStore = localFileStore
        self.bus = bus
        self.finalSiteInstaller = finalSiteInstaller
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
                .environmentObject(ambientGenerator)
                .environmentObject(npcMessenger)
                .environmentObject(playerPageState)
                .environmentObject(downloads)
                .environmentObject(saveDialog)
                .environmentObject(fileQuestTracker)
                .environmentObject(loveQuestTracker)
                .environmentObject(webmasterQuestTracker)
                .environmentObject(progressStore)
                .environmentObject(sessionStats)
                .onAppear {
                    ambientGenerator.start()
                    npcMessenger.start()
                    playerPageInstaller.start()
                    fileQuestTracker.start()
                    loveQuestTracker.start()
                    webmasterQuestTracker.start()
                    finalSiteInstaller.start()
                }
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
                Button("Прислать спам") {
                    ambientGenerator.forceDeliver("spam_nigerian_cosmonaut")
                }
                Button("Письмо от NPC") {
                    npcMessenger.forceSilence(from: "lena")
                }
                Button("Опубликовать страничку веб-мастера") {
                    playerPageInstaller.installNow()
                }
                Button("Квест: старт") {
                    fileQuestTracker.forceStart("three_files")
                }
                Button("Скачать Земфиру") {
                    fileQuestTracker.simulateDownload(contentId: "music_zemfira")
                }
                Button("Прикрепить и отправить Серёге") {
                    fileQuestTracker.simulateSend(contentId: "music_zemfira", to: "serega@pochta.su")
                }
                Button("Показать локальные файлы") {
                    printLocalFiles()
                }
                Button("Открыть гостевую «Полнолуния»") {
                    NotificationCenter.default.post(
                        name: .retroOpenURL,
                        object: nil,
                        userInfo: ["url": "http://polnolunie-fanclub.su/guestbook"]
                    )
                }
                Button("Love: старт") {
                    loveQuestTracker.forceStart(sympathyFor: "lena")
                }
                Button("Love: чат с Леной") {
                    NotificationCenter.default.post(
                        name: .retroOpenURL,
                        object: nil,
                        userInfo: ["url": "http://love.su/mail/lena"]
                    )
                }
                Button("Вебмастер: выставить счёт") {
                    webmasterQuestTracker.forceStart()
                }
                Button("Вебмастер: отправить квитанцию") {
                    webmasterQuestTracker.simulatePayment()
                }
                Button("Вебмастер: завершить сразу") {
                    webmasterQuestTracker.forceComplete()
                }
                Button("Artifacts: выдать все") {
                    for artifactId in ["artifact.collection", "artifact.page", "artifact.love"] {
                        bus.publish(.artifactEarned(ArtifactEarnedEvent(artifactId: artifactId)))
                    }
                }
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
                .environmentObject(fileQuestTracker)
                .environmentObject(loveQuestTracker)
                .environmentObject(webmasterQuestTracker)
                .environmentObject(progressStore)
                .environmentObject(sessionStats)
                .environmentObject(fileStore)
        }
        .defaultSize(width: 760, height: 560)
#endif
    }

    @Environment(\.openWindow) private var openWindow

    /// Debug helper: печатает все файлы в Store, сгруппированные по узлам.
    private func printLocalFiles() {
        let grouped = Dictionary(grouping: fileStore.instances, by: { $0.ownerNode })
        for node in grouped.keys.sorted() {
            let files = grouped[node] ?? []
            print("[Debug] 📁 \(node) (\(files.count))")
            for file in files {
                print("[Debug]   - \(file.content.name) [\(file.content.contentId)] \(FileSizeFormatter.format(file.content.sizeBytes))")
            }
        }
    }
}
