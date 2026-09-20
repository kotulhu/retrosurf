import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var connection: ConnectionManager
    @EnvironmentObject private var catalog: SiteCatalog
    @EnvironmentObject private var game: GameProgress
    @EnvironmentObject private var quests: QuestManager
    @EnvironmentObject private var mailbox: MailboxManager
    @StateObject private var engine = BrowserSimulator()
    @StateObject private var history = BrowserHistory()
    @State private var address = AggregatorPageBuilder.portalDomain
    @State private var currentHTML = ""
    @State private var currentBaseURL: URL?
    @State private var reloadToken = 0
    @State private var showCurator = false
    @State private var showLibrary = false
    @State private var lastOpenID: String?
    @State private var activeQuest: QuestExperienceInfo?

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(
                engine: engine,
                address: $address,
                onGo: handleGo,
                onHome: presentAggregator,
                onReload: reloadCurrent,
                onBack: goBack,
                onForward: goForward,
                canGoBack: history.canGoBack,
                canGoForward: history.canGoForward,
                onCurate: { showCurator = true },
                onLibrary: { showLibrary = true }
            )

            Group {
                if let activeQuest {
                    InteractiveExperienceRegistry.view(
                        for: activeQuest,
                        quests: quests,
                        mailbox: mailbox,
                        onBack: {
                            self.activeQuest = nil
                            presentAggregator()
                        },
                        onOpenSite: { target in openTarget(target) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WebView(html: currentHTML, baseURL: currentBaseURL, reloadToken: reloadToken, onNavigate: handleNavigate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            StatusBar(engine: engine)
        }
        .background(settings.skin.theme.contentBackground)
        .onAppear {
            engine.connection = connection
            presentAggregator()
        }
        .alert("Нет соединения", isPresented: blockedBinding) {
            Button("OK") {
                engine.acknowledgeBlocked()
            }
        } message: {
            Text("Подключитесь к интернету, чтобы загрузить страницу.")
        }
        .sheet(isPresented: $showCurator) {
            CuratorView()
        }
        .sheet(isPresented: $showLibrary) {
            CuratedLibraryView()
        }
    }

    private var blockedBinding: Binding<Bool> {
        Binding(
            get: { engine.connectionBlocked },
            set: { _ in engine.acknowledgeBlocked() }
        )
    }

    private func presentAggregator() {
        engine.cancelLoad()
        activeQuest = nil
        lastOpenID = nil
        address = AggregatorPageBuilder.portalDomain
        currentHTML = AggregatorPageBuilder.homeHTML(catalog: catalog, progress: game, quests: quests)
        currentBaseURL = nil
        reloadToken += 1
    }

    private func handleNavigate(_ target: String) {
        if target.lowercased() == AggregatorPageBuilder.portalDomain {
            presentAggregator()
            return
        }
        guard requireConnection() else { return }
        if let entry = catalog.entry(forDomain: target) {
            openSite(entry)
            return
        }
        showMissing(target)
    }

    private func handleGo() {
        let target = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.lowercased() == AggregatorPageBuilder.portalDomain {
            presentAggregator()
            return
        }
        guard requireConnection() else { return }
        if let entry = catalog.entry(forDomain: target) {
            openSite(entry)
            return
        }
        showMissing(target)
    }

    private func requireConnection() -> Bool {
        guard connection.isConnected else {
            engine.requestBlocked()
            return false
        }
        return true
    }

    private func openSite(_ entry: SiteEntry, recordHistory: Bool = true) {
        let lock = SiteAccess.status(for: entry, progress: game, quests: quests)
        guard !lock.locked else {
            showLocked(entry, reason: lock.reason ?? "Доступ ограничен")
            return
        }
        if recordHistory {
            history.navigate(to: HistoryEntry(siteID: entry.id, displayDomain: entry.displayDomain))
        }
        if case .interactive(let experienceID) = entry.source {
            lastOpenID = entry.id
            address = entry.displayDomain
            activeQuest = QuestExperienceInfo(experienceID: experienceID, siteID: entry.id)
            return
        }
        lastOpenID = entry.id
        address = entry.displayDomain
        let page = catalog.page(for: entry)
        let pendingHTML = page?.html ?? AggregatorPageBuilder.placeholderHTML(for: entry)
        let pendingBaseURL = page?.baseURL
        loadSite {
            if recordHistory {
                self.game.recordVisit(entry.id)
            }
            self.currentHTML = pendingHTML
            self.currentBaseURL = pendingBaseURL
            self.reloadToken += 1
        }
    }

    private func goBack() {
        guard let entry = history.back() else { return }
        openSiteFromHistory(entry)
    }

    private func goForward() {
        guard let entry = history.forward() else { return }
        openSiteFromHistory(entry)
    }

    private func openSiteFromHistory(_ entry: HistoryEntry) {
        guard let site = catalog.entry(id: entry.siteID) else {
            presentAggregator()
            return
        }
        openSite(site, recordHistory: false)
    }

    private func loadSite(completion: @escaping () -> Void) {
        engine.go(to: address, completion: completion)
    }

    private func openTarget(_ target: String) {
        guard requireConnection() else { return }
        if let entry = catalog.entry(id: target) {
            openSite(entry)
            return
        }
        if let entry = catalog.entry(forDomain: target) {
            openSite(entry)
            return
        }
        showMissing(target)
    }

    private func reloadCurrent() {
        guard requireConnection() else { return }
        if let id = lastOpenID, let entry = catalog.entry(id: id) {
            openSite(entry, recordHistory: false)
        } else {
            presentAggregator()
        }
    }

    private func showMissing(_ target: String) {
        engine.cancelLoad()
        activeQuest = nil
        lastOpenID = nil
        if !target.isEmpty {
            address = target
        }
        currentHTML = AggregatorPageBuilder.notFoundHTML(domain: target)
        currentBaseURL = nil
        reloadToken += 1
    }

    private func showLocked(_ entry: SiteEntry, reason: String) {
        engine.cancelLoad()
        activeQuest = nil
        lastOpenID = nil
        address = entry.displayDomain
        currentHTML = AggregatorPageBuilder.lockedHTML(for: entry, reason: reason)
        currentBaseURL = nil
        reloadToken += 1
    }
}