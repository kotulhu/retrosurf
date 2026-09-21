import Foundation

@MainActor
final class SiteRegistry {
    private var sites: [String: any InteractiveSite] = [:]

    func register(_ site: any InteractiveSite) {
        sites[site.descriptor.id] = site
    }

    func site(forHost host: String) -> (any InteractiveSite)? {
        let needle = host.trimmingCharacters(in: .whitespaces).lowercased()
        return sites.values.first { $0.descriptor.host.lowercased() == needle }
    }

    func site(for url: URL) -> (any InteractiveSite)? {
        guard let host = url.host else { return nil }
        return site(forHost: host)
    }

    func site(withID id: String) -> (any InteractiveSite)? {
        sites[id]
    }

    var allSites: [any InteractiveSite] {
        Array(sites.values)
    }
}
// MARK: - Part 1 · HomepageSite (своя страничка homepage.su)
// Интерактивный сайт по образу MailSite: сам публикует себя в SiteRegistry
// и отдаёт форму/страницу. Счётчик отзывов приходит из флага
// game.flags["homepage.feedback.N"] (читается через provider-замыкание).

/// State домашней странички.
struct HomepageState: Codable, Sendable {
    var isPublished = false
    var background: String = "stars"        // stars | clouds | construction
    var textColor: String = "#000000"
    var aboutMeText: String = ""
    var isShared = false

    static let defaults = HomepageState()
    static let backgroundOptions: [[String: String]] = [
        ["id": "stars", "name": "Звёздное небо"],
        ["id": "clouds", "name": "Облака"],
        ["id": "construction", "name": "Страница в разработке"]
    ]
}

/// Контент опубликованной статической страницы, которую регистрирует
/// `registerStaticSite` — тот же renderer, что обслуживает user-added.
struct StaticSiteContent: Codable, Sendable {
    var html: String
}

/// Готовая статическая страница (публикация homepage.su). Сразу после
/// `registerStaticSite` попадает в реестр — без перезапуска.
final class StaticSite: BaseInteractiveSite<StaticSiteContent> {
    init(host: String, displayName: String, html: String) {
        super.init(
            descriptor: SiteDescriptor(
                id: host, host: host, displayName: displayName,
                iconSystemName: "house"
            ),
            initialState: StaticSiteContent(html: html)
        )
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        guard let url = url(for: request) else { return .failure("Host not found") }
        return .page(SitePage(url: url, title: descriptor.displayName, html: state.html))
    }

    private func url(for request: SiteRequest) -> URL? {
        switch request {
        case .open(let u): return u
        default: return URL(string: "http://\(descriptor.host)/")
        }
    }
}

/// «Своя страничка» — две ветки:
///  · не опубликована → форма публикации (фон / цвет текста / «Обо мне») →
///    кнопка «Опубликовать» → .registerStaticSite + isPublished = true;
///  · опубликована → витрина + кнопка «Разослать ссылку трём друзьям» →
///    isShared = true, флаг homepageShared; снизу «Отзывов получено: N/3».
/// Счётчик отзывов: feedbackCountProvider читает game.flags[homepage.feedback.N].
final class HomepageSite: BaseInteractiveSite<HomepageState> {
    static let host = "homepage.su"

    var feedbackCountProvider: () -> Int = { 0 }

    init() {
        super.init(
            descriptor: SiteDescriptor(
                id: "homepage-su", host: Self.host, displayName: "Моя страничка",
                iconSystemName: "house"
            ),
            initialState: HomepageState.defaults
        )
    }

    var publishedHTML: String {
        HomepageTemplates.publishedPage(state: state, isShared: state.isShared)
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url):
            return await open(url)
        case .submit(let url, let form):
            return await submit(url, form: form)
        case .invoke:
            return .failure("404")
        }
    }

    private func open(_ url: URL) async -> SiteResponse {
        if !state.isPublished {
            return page(path: "/", title: "Создать страничку", html: HomepageTemplates.publishForm(state: state))
        }
        if !state.isShared {
            return page(path: "/", title: "Моя страничка", html: HomepageTemplates.publishedPage(state: state, isShared: false))
        }
        return page(path: "/", title: "Моя страничка", html: HomepageTemplates.publishedPage(state: state, isShared: true))
    }

    private func submit(_ url: URL, form: [String: String]) async -> SiteResponse {
        func g(_ key: String) -> String? {
            form[key] ?? form[key.lowercased()]
                ?? form.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        }
        let path = url.path == "" ? "/" : url.path
        switch path {
        case "/publish":
            state.isPublished = true
            state.background = g("background") ?? state.background
            state.textColor = g("textColor") ?? state.textColor
            state.aboutMeText = g("aboutMeText") ?? state.aboutMeText
            let page = SitePage(url: Self.resolve("/"), title: "Моя страничка",
                                html: HomepageTemplates.publishedPage(state: state, isShared: false))
            return .compound([
                .page(page),
                .effect(.registerStaticSite(SiteDescriptor(
                    id: Self.host, host: Self.host, displayName: "Моя страничка",
                    iconSystemName: "house"
                ), publishedHTML))
            ])
        case "/share":
            state.isShared = true
            return .compound([
                .page(SitePage(url: Self.resolve("/"), title: "Моя страничка",
                               html: HomepageTemplates.publishedPage(state: state, isShared: true))),
                .effect(.setFlag("homepageShared", true))
            ])
        default:
            return .failure("404: \(path)")
        }
    }

    private func page(path: String, title: String, html: String) -> SiteResponse {
        .page(SitePage(url: Self.resolve(path), title: title, html: html))
    }

    static func resolve(_ path: String) -> URL {
        URL(string: "http://\(host)\(path == "/" ? "" : path)") ?? URL(string: "http://\(host)/")!
    }
}

/// HTML-шаблоны домашней странички — 3 фона, подстановка цветов, «Обо мне».
enum HomepageTemplates {
    static func publishForm(state: HomepageState) -> String {
        let bgColor = bgHex(state.background)
        let options = HomepageState.backgroundOptions.map { opt in
            let selected = opt["id"] == state.background ? " selected" : ""
            return "<option value=\"\(opt["id"] ?? "")\"\(selected)>\(opt["name"] ?? "")</option>"
        }.joined()
        return """
        <html><head><meta charset="utf-8"><title>Создать страничку</title>
        <style>body{background:#\(bgColor);color:#000;font-family:monospace;padding:28px}</style>
        </head><body>
        <h1>Создать свою страничку</h1>
        <form action="/publish" method="POST">
          <label>Фон:<select name="background">\(options)</select></label><br><br>
          <label>Цвет текста:<input name="textColor" type="color" value="#000000"></label><br><br>
          <label>Обо мне:<br><textarea name="aboutMeText" rows="4" cols="40"></textarea></label><br><br>
          <button>Опубликовать</button>
        </form></body></html>
        """
    }

    static func publishedPage(state: HomepageState, isShared: Bool) -> String {
        let bgColor = bgHex(state.background)
        let textColor = normalizeHex(state.textColor)
        let feedbackCount = 0
        let counter = isShared
            ? "<p style='color:#0a0'>Отзывов получено: <b>\(feedbackCount)/3</b></p>"
            : "<form action='/share' method='POST'><button>Разослать ссылку трём друзьям</button></form>"
        return """
        <html><head><meta charset="utf-8"><title>Моя страничка</title>
        <style>body{background:#\(bgColor);color:#\(textColor);font-family:monospace;padding:28px}</style>
        </head><body>
        <h1>Добро пожаловать на мою страничку!</h1>
        <p>\(state.aboutMeText.isEmpty ? "Здесь пока пусто — загляни позже." : state.aboutMeText)</p>
        \(counter)
        </body></html>
        """
    }

    static func bgHex(_ id: String) -> String {
        switch id {
        case "clouds": return "dfe9f3"
        case "construction": return "f9e79f"
        default: return "0d1b2a" // stars
        }
    }

    static func normalizeHex(_ hex: String) -> String {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count != 6 { return "000000" }
        return value
    }
}
