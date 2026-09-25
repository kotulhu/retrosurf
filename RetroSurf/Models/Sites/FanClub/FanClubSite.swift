import Foundation

/// Интерактивный фан-клуб группы «Полнолуние»: биография, состав,
/// дискография, тексты песен, MP3-каталог, гостевая книга и ссылки.
/// Контент полностью из content.json (FanClubContent), архивируемое
/// состояние — только записи гостевой, оставленные игроком.
@MainActor
final class FanClubSite: BaseInteractiveSite<FanClubState> {
    static let host = "polnolunie-fanclub.su"

    private let content: FanClubContent

    init(content: FanClubContent) {
        self.content = content
        super.init(
            descriptor: SiteDescriptor(
                id: "polnolunie_fanclub",
                host: Self.host,
                displayName: "Полнолуние — фан-клуб",
                iconSystemName: "moon.stars"
            ),
            initialState: FanClubState()
        )
    }

    override func resetGameplay() {
        state = FanClubState()
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url):
            return handleGet(url)
        case .submit(let url, let form):
            if url.path == "/guestbook", !form.isEmpty {
                return postGuestbook(form)
            }
            return handleGet(url)
        case .invoke(let action, _):
            return .failure("404: \(action)")
        case .composeAttach, .composeRemoveAttachment:
            return .failure("404")
        }
    }

    // MARK: - Routing

    private func handleGet(_ url: URL) -> SiteResponse {
        guard let host = url.host?.lowercased(), host == Self.host else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        let path = url.path.isEmpty ? "/" : url.path
        switch path {
        case "/": return indexPage()
        case "/about": return aboutPage()
        case "/members": return membersPage()
        case "/discography": return discographyPage()
        case "/songs": return songsPage()
        case "/mp3": return mp3Page()
        case "/guestbook": return guestbookPage(message: nil)
        case "/links": return linksPage()
        default:
            if path.hasPrefix("/song/") {
                return songPage(String(path.dropFirst("/song/".count)))
            }
            if path.hasPrefix("/mp3/download/") {
                return downloadResponse(String(path.dropFirst("/mp3/download/".count)))
            }
            return .failure("404: \(path)")
        }
    }

    // MARK: - Pages

    private func indexPage() -> SiteResponse {
        let body = FanClubTemplates.indexBody(site: content.site)
        return .page(SitePage(
            url: resolve("/"),
            title: content.site.title,
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: content.site.title,
                body: body,
                active: nil
            )
        ))
    }

    private func aboutPage() -> SiteResponse {
        let body = FanClubTemplates.aboutBody(content: content)
        return .page(SitePage(
            url: resolve("/about"),
            title: "О группе",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "О группе",
                body: body,
                active: "about"
            )
        ))
    }

    private func membersPage() -> SiteResponse {
        let body = FanClubTemplates.membersBody(content: content)
        return .page(SitePage(
            url: resolve("/members"),
            title: "Состав",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "Состав",
                body: body,
                active: "members"
            )
        ))
    }

    private func discographyPage() -> SiteResponse {
        let body = FanClubTemplates.discographyBody(content: content)
        return .page(SitePage(
            url: resolve("/discography"),
            title: "Дискография",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "Дискография",
                body: body,
                active: "discography"
            )
        ))
    }

    private func songsPage() -> SiteResponse {
        let body = FanClubTemplates.songsBody(content: content)
        return .page(SitePage(
            url: resolve("/songs"),
            title: "Песни",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "Песни",
                body: body,
                active: "songs"
            )
        ))
    }

    private func songPage(_ songID: String?) -> SiteResponse {
        guard let songID, let song = content.song(id: songID) else {
            return .failure("404: /song/\(songID ?? "")")
        }
        let body = FanClubTemplates.songBody(song: song)
        return .page(SitePage(
            url: resolve("/song/\(songID)"),
            title: song.title,
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: song.title,
                body: body,
                active: "songs"
            )
        ))
    }

    private func mp3Page() -> SiteResponse {
        let body = FanClubTemplates.mp3Body(content: content)
        return .page(SitePage(
            url: resolve("/mp3"),
            title: "MP3",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "MP3",
                body: body,
                active: "mp3"
            )
        ))
    }

    private func downloadResponse(_ mp3ID: String) -> SiteResponse {
        guard let mp3 = content.mp3(id: mp3ID) else {
            return .failure("404: /mp3/download/\(mp3ID)")
        }
        return .download(SiteDownload(
            id: mp3.id,
            fileName: mp3.fileName,
            sizeBytes: mp3.sizeBytes,
            sourceURL: resolve("/mp3/download/\(mp3.id)"),
            hasVirus: mp3.hasVirus,
            category: "music",
            description: mp3.description
        ))
    }

    private func guestbookPage(message: String?) -> SiteResponse {
        let body = FanClubTemplates.guestbookBody(
            content: content,
            entries: mergedEntries(),
            message: message
        )
        return .page(SitePage(
            url: resolve("/guestbook"),
            title: "Гостевая книга",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "Гостевая книга",
                body: body,
                active: "guestbook"
            )
        ))
    }

    private func linksPage() -> SiteResponse {
        let body = FanClubTemplates.linksBody()
        return .page(SitePage(
            url: resolve("/links"),
            title: "Ссылки",
            html: FanClubTemplates.fullHTML(
                site: content.site,
                title: "Ссылки",
                body: body,
                active: "links"
            )
        ))
    }

    // MARK: - Guestbook

    /// Seeds (из content.json) + записи игрока, по убыванию времени.
    /// Seeds не хранятся в state: timestamp считается на каждый рендер.
    func mergedEntries() -> [GuestbookEntry] {
        let now = Date()
        var entries = content.seedGuestbook.map { seed in
            GuestbookEntry(
                id: seed.id,
                author: seed.author,
                email: seed.email,
                text: seed.text,
                timestamp: now.addingTimeInterval(-Double(seed.daysAgo) * 86400)
            )
        }
        entries.append(contentsOf: state.playerEntries)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    private func postGuestbook(_ form: [String: String]) -> SiteResponse {
        let author = (form["author"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (form["email"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (form["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if author.isEmpty || text.isEmpty {
            return guestbookPage(message: "Заполните имя и сам текст записи — без них запись не добавится.")
        }

        state.playerEntries.append(GuestbookEntry(
            id: "p\(state.nextEntryId)",
            author: author,
            email: email,
            text: text,
            timestamp: Date()
        ))
        state.nextEntryId += 1
        return guestbookPage(message: "Спасибо! Запись добавлена в гостевую книгу.")
    }

    // MARK: - Helpers

    private func resolve(_ path: String) -> URL {
        URL(string: "http://\(Self.host)\(path)")!
    }
}