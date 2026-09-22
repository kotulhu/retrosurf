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
    var account: HomepageAccount?
    var session: HomepageSession?

    static let defaults = HomepageState()
    static let backgroundOptions: [[String: String]] = [
        ["id": "stars", "name": "Звёздное небо"],
        ["id": "clouds", "name": "Облака"],
        ["id": "construction", "name": "Страница в разработке"]
    ]
}

struct HomepageAccount: Codable, Sendable {
    let login: String
    let password: String
    let email: String
    let createdAt: Date
}

struct HomepageSession: Codable, Sendable {
    let login: String
    let loggedInAt: Date
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

    private let mailSite: MailSite
    var feedbackCountProvider: () -> Int = { 0 }

    init(mailSite: MailSite) {
        self.mailSite = mailSite
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
        if url.path.hasPrefix("/p/") {
            return page(path: url.path, title: "Личная страничка", html: HomepageTemplates.stubPage(path: url.path))
        }
        if url.path == "/logout" {
            state.session = nil
            return page(path: "/", title: "Люди.su", html: HomepageTemplates.catalogPage(state: state, notice: "Вы вышли из своей учётной записи."))
        }
        if !state.isPublished {
            return page(path: "/", title: "Каталог страничек", html: HomepageTemplates.catalogPage(state: state))
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
        case "/register":
            return register(form)
        case "/login":
            return login(form)
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

    private func register(_ form: [String: String]) -> SiteResponse {
        let login = formValue("login", in: form).trimmingCharacters(in: .whitespacesAndNewlines)
        let password = formValue("password", in: form)
        let email = formValue("email", in: form).trimmingCharacters(in: .whitespacesAndNewlines)

        guard state.account == nil else {
            return catalogResponse("На Люди.su уже зарегистрирован пользователь \(state.account!.login).")
        }
        guard !login.isEmpty, !password.isEmpty, !email.isEmpty else {
            return catalogResponse("Заполните логин, пароль и адрес электронной почты.")
        }
        guard email.contains("@") else {
            return catalogResponse("Укажите корректный адрес электронной почты.")
        }

        let account = HomepageAccount(login: login, password: password, email: email, createdAt: Date())
        state.account = account
        state.session = HomepageSession(login: login, loggedInAt: Date())
        mailSite.deliver(
            MailDraft(
                from: "admin@\(Self.host)",
                subject: "Добро пожаловать на Люди.su",
                bodyHTML: "<p>Здравствуйте, <b>\(HomepageTemplates.escapeHTML(login))</b>!</p><p>Ваша учётная запись на Люди.su создана.</p><p>Логин: <b>\(HomepageTemplates.escapeHTML(login))</b><br>Пароль: <b>\(HomepageTemplates.escapeHTML(password))</b></p><p>Сохраните это письмо, чтобы не забыть данные для входа.</p>",
                tag: "homepage-registration",
                timestamp: Date(),
                folder: .inbox
            )
        )
        return catalogResponse("Регистрация завершена. Письмо с логином и паролем отправлено на вашу Почту.SU.")
    }

    private func login(_ form: [String: String]) -> SiteResponse {
        guard let account = state.account else {
            return catalogResponse("Сначала зарегистрируйтесь на Люди.su.")
        }
        let login = formValue("login", in: form).trimmingCharacters(in: .whitespacesAndNewlines)
        let password = formValue("password", in: form)
        guard login == account.login, password == account.password else {
            return catalogResponse("Неверный логин или пароль.")
        }
        state.session = HomepageSession(login: login, loggedInAt: Date())
        return catalogResponse("С возвращением, \(login)!")
    }

    private func formValue(_ key: String, in form: [String: String]) -> String {
        form[key] ?? form[key.lowercased()]
            ?? form.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
            ?? ""
    }

    private func catalogResponse(_ notice: String) -> SiteResponse {
        page(path: "/", title: "Люди.su", html: HomepageTemplates.catalogPage(state: state, notice: notice))
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
    static func catalogPage(state: HomepageState, notice: String? = nil) -> String {
        let catalog = [
            "Андрей из Самары", "Лена и её кот Барсик", "Димон 2000", "Наташа Солнечная",
            "Серёга Воронеж", "Катюша", "Михаил, 11-Б", "Оля любит аниме",
            "Вовка-Рокер", "Марина", "Паша из сети", "Света", "Игорь",
            "Таня", "Макс", "Люба", "Рома", "Ксюша", "Денис", "Аня"
        ]
        let catalogLinks = catalog.enumerated().map { index, name in
            "<li><a href=\"/p/\(index + 1).html\">\(name)</a></li>"
        }.joined()
        let recent = [
            (20, "Аня"), (19, "Денис"), (18, "Ксюша"), (17, "Рома"), (16, "Люба")
        ].map { number, name in
            "<li><a href=\"/p/\(number).html\">\(name)</a></li>"
        }.joined()
        let accountBlock: String
        if let session = state.session {
            accountBlock = "<p class=\"hint\">Вы вошли как <b>\(escapeHTML(session.login))</b>.<br><a href=\"/logout\">Выйти</a></p>"
        } else if state.account != nil {
            accountBlock = "<p class=\"hint\">Уже зарегистрированы? Войдите в свой аккаунт.</p>"
        } else {
            accountBlock = "<p class=\"hint\">Регистрация бесплатная!</p>"
        }
        let noticeBlock = notice.map { "<p class=\"notice\">\(escapeHTML($0))</p>" } ?? ""
        return """
        <html><head><meta charset="utf-8"><title>Люди.su - личные странички</title>
        <style>
        body{margin:0;background:#e7e2cf;color:#222;font:13px 'Times New Roman',serif}
        .page{width:760px;margin:18px auto 30px}.logo{text-align:center;color:#8c1919;font-size:38px;font-weight:bold}
        .tagline{text-align:center;margin:2px 0 14px;color:#555}.columns{width:100%;border-collapse:collapse}
        .columns td{vertical-align:top;padding:0 6px}.panel{background:#fffdf4;border:1px solid #555;padding:9px}
        h2{margin:-9px -9px 9px;padding:4px 7px;background:#d6c79d;border-bottom:1px solid #555;font-size:16px;text-align:center}
        h3{margin:10px 0 4px;font-size:14px}.field{width:100%;box-sizing:border-box;margin:2px 0 6px;border:1px solid #777}
        .button{font:13px 'Times New Roman',serif;margin-top:2px}.hint{font-size:11px;color:#555}.notice{background:#e3f3d9;border:1px solid #698d58;padding:6px}.catalog{margin:0;padding-left:22px;line-height:1.45}
        a{color:#0000aa}a:visited{color:#660066}.new{color:#087d08;font-weight:bold}.footer{text-align:center;margin-top:13px;font-size:11px;color:#666}
        </style>
        </head><body>
        <div class="page">
        <div class="logo">Люди.su</div>
        <div class="tagline">Личные странички пользователей русской сети</div>
        <table class="columns"><tr>
        <td width="185"><div class="panel">
        <h2>Вход для своих</h2>
        <form method="get" action="http://homepage.su/login"><b>Логин:</b><input class="field" type="text" name="login"><b>Пароль:</b><input class="field" type="password" name="password"><input class="button" type="submit" value="Войти"></form>
        <p class="hint"><a href="#">Забыли пароль?</a></p>
        <h3>Ещё не с нами?</h3>
        <form method="get" action="http://homepage.su/register"><b>Придумайте логин:</b><input class="field" type="text" name="login"><b>Пароль:</b><input class="field" type="password" name="password"><b>Ваш e-mail:</b><input class="field" type="text" name="email"><input class="button" type="submit" value="Зарегистрироваться"></form>
        \(accountBlock)
        </div></td>
        <td width="385"><div class="panel">
        <h2>Каталог личных страничек</h2>
        \(noticeBlock)
        <p>Здесь живут домашние странички наших пользователей. Выберите, к кому заглянуть в гости:</p>
        <ol class="catalog">\(catalogLinks)</ol>
        <p class="hint">Хотите попасть в каталог? Зарегистрируйтесь на Люди.su.</p>
        </div></td>
        <td width="190"><div class="panel">
        <h2>Последние добавленные</h2>
        <p class="hint"><span class="new">new!</span> Свежие странички:</p>
        <ol class="catalog">\(recent)</ol>
        <p class="hint"><a href="#">Все новые странички</a></p>
        </div></td>
        </tr></table>
        <div class="footer">Люди.su &copy; 2001. Сделано людьми для людей.</div>
        </div>
        </body></html>
        """
    }

    static func stubPage(path: String) -> String {
        let name = path.replacingOccurrences(of: "/p/", with: "").replacingOccurrences(of: ".html", with: "")
        return """
        <html><head><meta charset="utf-8"><title>Личная страничка №\(name)</title>
        <style>body{background:#fff8e7;color:#333;font-family:monospace;padding:24px}</style>
        </head><body>
        <h1>Личная страничка №\(name)</h1>
        <p>Здесь скоро появится настоящее содержимое сайта.</p>
        <p><a href="/">← На главную</a></p>
        </body></html>
        """
    }

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

    static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
