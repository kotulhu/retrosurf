import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var connection: ConnectionManager
    @EnvironmentObject private var catalog: SiteCatalog
    @EnvironmentObject private var game: GameProgress
    @EnvironmentObject private var quests: QuestManager
    @EnvironmentObject private var mailbox: MailboxManager
    @EnvironmentObject private var sites: SiteSession
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
    @State private var siteAlert: String?

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
                    WebView(
                        html: currentHTML,
                        baseURL: currentBaseURL,
                        reloadToken: reloadToken,
                        onNavigate: handleNavigate
                    ) { host in
                        sites.registry.site(forHost: host) != nil
                    }
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
        .alert(alertTitle, isPresented: alertBinding) {
            Button("OK") {
                engine.acknowledgeBlocked()
                siteAlert = nil
            }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showCurator) {
            CuratorView()
        }
        .sheet(isPresented: $showLibrary) {
            CuratedLibraryView()
        }
    }

    // MARK: - Alerts

    private var alertTitle: String {
        siteAlert == nil ? "Нет соединения" : "Внимание"
    }

    private var alertMessage: String {
        siteAlert ?? "Подключитесь к интернету, чтобы загрузить страницу."
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { engine.connectionBlocked || siteAlert != nil },
            set: { if !$0 { engine.acknowledgeBlocked(); siteAlert = nil } }
        )
    }

    // MARK: - Home

    private func presentAggregator() {
        engine.cancelLoad()
        activeQuest = nil
        lastOpenID = nil
        address = AggregatorPageBuilder.portalDomain
        currentHTML = AggregatorPageBuilder.homeHTML(catalog: catalog, progress: game, quests: quests)
        currentBaseURL = nil
        reloadToken += 1
        persistSites()
    }

    // MARK: - Navigation entry points

    private func handleNavigate(_ raw: String) {
        navigate(raw: raw)
    }

    private func handleGo() {
        navigate(raw: address)
    }

    /// Normalize an input (retrosurf://host/…, http://host/…, bare host/…) to
    /// a bare "host/path?query" string the rest of the browser understands.
    private func normalized(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("retrosurf://") {
            s = String(s.dropFirst("retrosurf://".count))
        }
        return SiteCatalog.normalizedDomain(s)
    }

    private func navigate(raw rawInput: String) {
        let norm = normalized(rawInput)
        guard !norm.isEmpty else { return }
        guard let url = URL(string: "http://" + norm), let host = url.host else {
            showMissing(norm)
            return
        }
        if host == AggregatorPageBuilder.portalDomain {
            presentAggregator()
            return
        }
        guard requireConnection() else { return }
        Task {
            await dispatch(url)
            persistSites()
        }
    }

    private func requireConnection() -> Bool {
        guard connection.isConnected else {
            engine.requestBlocked()
            return false
        }
        return true
    }

    // MARK: - Site routing (Session)

    /// Route a URL to a registered interactive site (pochta.su…), a catalog
    /// site, or the not-found page. GET form fields travel in the query string.
    private func dispatch(_ url: URL) async {
        let (cleanURL, form) = splitForm(from: url)
        guard let host = cleanURL.host else {
            showMissing(url.absoluteString)
            return
        }
        if sites.registry.site(forHost: host) != nil {
            let request: SiteRequest = form.map { .submit(cleanURL, $0) } ?? .open(cleanURL)
            do {
                let response = await sites.dispatch(request)
                try await apply(response, depth: 0)
            } catch LoadInterruption.disconnected {
                showReconnect(retry: normalized(cleanURL.absoluteString))
            } catch is CancellationError {
                // Superseded by Stop/Home — leave the UI where it is.
            } catch {
                showReconnect(retry: normalized(cleanURL.absoluteString))
            }
            return
        }
        if let entry = catalog.entry(forDomain: host) {
            openSite(entry)
            return
        }
        showMissing(host)
    }

    private func splitForm(from url: URL) -> (url: URL, form: [String: String]?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return (url, nil)
        }
        var form: [String: String] = [:]
        for item in items {
            form[item.name] = item.value ?? ""
        }
        var clean = components
        clean.query = nil
        return (clean.url ?? url, form)
    }

    // MARK: - Applying a SiteResponse (universal load rule)

    /// Rules: .page pays baseLatency + bytes/speed (may die mid-transfer);
    /// .redirect pays baseLatency only; .alert/.effect/.failure are instant;
    /// .compound resolves as one transition, its .page using its own size.
    private func apply(_ response: SiteResponse, depth: Int) async throws {
        guard depth < 10 else { throw LoadInterruption.disconnected }
        switch response {
        case .page(let page):
            try await renderPage(page)
        case .redirect(let url):
            try await engine.redirectDelay()
            address = normalized(url.absoluteString)
            await dispatch(url)
        case .alert(let text):
            siteAlert = text
        case .effect(let effect):
            applyEffect(effect)
        case .compound(let list):
            for item in list {
                try await apply(item, depth: depth + 1)
            }
        case .failure(let message):
            showFailure(message, retry: normalized(address))
        }
    }

    private func renderPage(_ page: SitePage) async throws {
        try await engine.loadBytes(max(page.html.utf8.count, 1))
        currentHTML = page.html
        currentBaseURL = page.url
        address = normalized(page.url.absoluteString)
        reloadToken += 1
    }

    private func applyEffect(_ effect: SiteEffect) {
        switch effect {
        case .setFlag(let name, let value):
            guard value else { return }
            game.setFlag(name)
            if name == "mail.registered" {
                quests.markCompleted(QuestManager.registrationQuestID)
                if let lastOpenID {
                    game.recordVisit(lastOpenID)
                }
            }
        case .addItem, .advanceQuest, .endGame:
            break
        }
    }

    // MARK: - Reconnect / failure pages

    private func showReconnect(retry: String) {
        engine.cancelLoad()
        activeQuest = nil
        currentHTML = AggregatorPageBuilder.disconnectedHTML(retryTarget: retry)
        currentBaseURL = nil
        reloadToken += 1
    }

    private func showFailure(_ message: String, retry: String) {
        engine.cancelLoad()
        activeQuest = nil
        currentHTML = AggregatorPageBuilder.siteErrorHTML(message: message, retryTarget: retry)
        currentBaseURL = nil
        reloadToken += 1
    }

    // MARK: - Catalog sites

    private func openSite(_ entry: SiteEntry, recordHistory: Bool = true) {
        let lock = SiteAccess.status(for: entry, progress: game, quests: quests)
        guard !lock.locked else {
            showLocked(entry, reason: lock.reason ?? "Доступ ограничен")
            return
        }
        if recordHistory {
            history.navigate(to: HistoryEntry(siteID: entry.id, displayDomain: entry.displayDomain))
        }
        lastOpenID = entry.id
        address = entry.displayDomain

        if case .interactive(let experienceID) = entry.source {
            guard sites.registry.site(forHost: entry.displayDomain) != nil else {
                // Not yet implemented as a real web site — SwiftUI stand-in.
                activeQuest = QuestExperienceInfo(experienceID: experienceID, siteID: entry.id)
                return
            }
            // Real web site: buffer the visit, then fetch its start page.
            game.recordVisit(entry.id)
            guard let url = URL(string: "http://" + entry.displayDomain + "/") else { return }
            Task {
                await dispatch(url)
                persistSites()
            }
            return
        }

        // Static site: its HTML is a page too — same byte-based load rule.
        let page = catalog.page(for: entry)
        let pendingHTML = page?.html ?? AggregatorPageBuilder.placeholderHTML(for: entry)
        let pendingBaseURL = page?.baseURL
        Task {
            do {
                try await engine.loadBytes(max(pendingHTML.utf8.count, 1))
                if recordHistory {
                    game.recordVisit(entry.id)
                }
                self.currentHTML = pendingHTML
                self.currentBaseURL = pendingBaseURL
                self.reloadToken += 1
            } catch LoadInterruption.disconnected {
                self.showReconnect(retry: entry.displayDomain)
            } catch {
                // Cancelled.
            }
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
            if sites.registry.site(forHost: entry.displayDomain) != nil {
                let norm = normalized(address)
                guard let url = URL(string: "http://" + norm) else {
                    openSite(entry, recordHistory: false)
                    return
                }
                Task {
                    await dispatch(url)
                    persistSites()
                }
            } else {
                openSite(entry, recordHistory: false)
            }
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

    private func persistSites() {
        let snapshots = sites.snapshotAll()
        UserDefaults.standard.set(snapshots, forKey: SiteSession.snapshotsDefaultsKey)
        UserDefaults.standard.synchronize()
    }
}