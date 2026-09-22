import Foundation

final class HomepageSite: BaseInteractiveSite<HomepageState> {
    static let host = "homepage.su"

    private let mailSite: MailSite
    private let messageScheduler: MessageScheduler

    init(mailSite: MailSite, messageScheduler: MessageScheduler) {
        self.mailSite = mailSite
        self.messageScheduler = messageScheduler
        super.init(
            descriptor: SiteDescriptor(
                id: "homepage-su", host: Self.host, displayName: "Моя страничка",
                iconSystemName: "house"
            ),
            initialState: HomepageState.defaults
        )
    }

    override func resetGameplay() {
        state = HomepageState.defaults
    }

    var publishedHTML: String {
        HomepageTemplates.publishedPage(
            state: state,
            isShared: state.isShared,
            feedbackCount: state.feedbackCount
        )
    }

    /// Records one friend feedback letter. Returns true when the third arrives.
    @discardableResult
    func recordFeedback() -> Bool {
        guard state.feedbackCount < 3 else { return false }
        state.feedbackCount += 1
        return state.feedbackCount >= 3
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
            return page(path: url.path, title: "Личная страничка", html: HomepageTemplates.personalPage(path: url.path))
        }
        switch url.path {
        case "/logout":
            state.session = nil
            return page(path: "/", title: "Люди.su", html: HomepageTemplates.catalogPage(state: state, notice: "Вы вышли из своей учётной записи."))
        case "/editor":
            guard isAuthenticated else {
                return catalogResponse("Войдите, чтобы редактировать личную страничку.")
            }
            return page(path: "/editor", title: "Редактор страницы", html: HomepageTemplates.editorPage(state: state))
        case "/editor/photo":
            guard isAuthenticated else {
                return catalogResponse("Войдите, чтобы добавить фотографию.")
            }
            return .effect(.selectLocalPhoto(Self.host))
        case "/my-page":
            return personalPageResponse()
        default:
            return page(path: "/", title: "Каталог страничек", html: HomepageTemplates.catalogPage(state: state))
        }
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
        case "/editor/save":
            return savePage(form)
        case "/editor/photo":
            guard isAuthenticated else {
                return page(path: "/editor", title: "Редактор страницы",
                            html: HomepageTemplates.editorPage(state: state, error: "Сначала войдите в свою учётную запись."))
            }
            let aboutMe = formValue("aboutMeText", in: form).trimmingCharacters(in: .whitespacesAndNewlines)
            state.aboutMeText = aboutMe
            return .effect(.selectLocalPhoto(Self.host))
        case "/publish":
            guard isAuthenticated else { return catalogResponse("Войдите, чтобы опубликовать страницу.") }
            state.isPublished = true
            state.background = g("background") ?? state.background
            state.textColor = g("textColor") ?? state.textColor
            state.aboutMeText = g("aboutMeText") ?? state.aboutMeText
            let page = SitePage(url: Self.resolve("/"), title: "Моя страничка",
                                html: HomepageTemplates.publishedPage(state: state, isShared: false, feedbackCount: state.feedbackCount))
            return .compound([
                .page(page),
                .effect(.registerStaticSite(SiteDescriptor(
                    id: Self.host, host: Self.host, displayName: "Моя страничка",
                    iconSystemName: "house"
                ), publishedHTML))
            ])
        case "/share":
            guard isAuthenticated else { return catalogResponse("Войдите, чтобы поделиться ссылкой на страницу.") }
            let email = (g("email") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty, email.contains("@") else {
                return personalPageResponse(notice: "Укажите e-mail друга, чтобы отправить ему ссылку на страничку.")
            }
            guard !state.invitedFriends.contains(email) else {
                return personalPageResponse(notice: "Ссылку на этот адрес вы уже отправляли. Может быть, друг ещё не заглянул на почту?")
            }
            guard state.invitedFriends.count < 3 else {
                return personalPageResponse(notice: "Вы уже разослали ссылку трём друзьям. Осталось дождаться их писем!")
            }
            state.invitedFriends.append(email)
            scheduleFriendFeedback(to: email, order: state.invitedFriends.count)
            state.isShared = true
            return .compound([
                .page(SitePage(url: Self.resolve("/my-page"), title: "Моя страничка",
                               html: HomepageTemplates.publishedPage(
                                   state: state,
                                   isShared: true,
                                   feedbackCount: state.feedbackCount,
                                   isOwner: true,
                                   notice: "Ссылка на страничку отправлена другу (\(HomepageTemplates.escapeHTML(email))). Когда друг заглянет, вам придёт письмо."
                               ))),
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

    private func savePage(_ form: [String: String]) -> SiteResponse {
        guard isAuthenticated else {
            return page(path: "/editor", title: "Редактор страницы",
                        html: HomepageTemplates.editorPage(state: state, error: "Сначала войдите в свою учётную запись, чтобы сохранить изменения."))
        }
        let aboutMe = formValue("aboutMeText", in: form).trimmingCharacters(in: .whitespacesAndNewlines)
        state.aboutMeText = aboutMe
        state.isPublished = true
        return .compound([
            .page(SitePage(url: Self.resolve("/my-page"), title: "Моя страничка",
                           html: HomepageTemplates.publishedPage(state: state, isShared: state.isShared, feedbackCount: state.feedbackCount, isOwner: true))),
            .alert("Страница сохранена и опубликована.")
        ])
    }

    private var isAuthenticated: Bool {
        guard let account = state.account, let session = state.session else { return false }
        return account.login == session.login
    }

    @discardableResult
    func storePhoto(from sourceURL: URL) -> Bool {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension.lowercased()
        let destination = Self.photosDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try fileManager.createDirectory(at: Self.photosDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destination)
            if let previous = state.photoFilename {
                try? fileManager.removeItem(at: Self.photosDirectory.appendingPathComponent(previous))
            }
            state.photoFilename = destination.lastPathComponent
            state.photoURL = nil
            return true
        } catch {
            return false
        }
    }

    private static var photosDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroSurf", isDirectory: true)
            .appendingPathComponent("HomepagePhotos", isDirectory: true)
    }

    private func personalPageResponse(notice: String? = nil) -> SiteResponse {
        page(
            path: "/my-page",
            title: "Моя страничка",
            html: HomepageTemplates.publishedPage(
                state: state,
                isShared: state.isShared,
                feedbackCount: state.feedbackCount,
                isOwner: isAuthenticated,
                notice: notice
            )
        )
    }

    private func scheduleFriendFeedback(to email: String, order: Int) {
        let localPart = String(email.split(separator: "@").first ?? "друг")
        let displayName = localPart.capitalized
        let sender = Sender(
            archetypeId: "friend",
            name: SenderName(full: displayName, firstName: displayName, login: localPart),
            address: email,
            kind: .human,
            gender: .none
        )
        messageScheduler.schedule(
            channel: .mail,
            targetSiteId: "mail",
            message: QuestMessage(
                questID: "homepage-feedback-\(order)",
                sender: sender,
                subject: "Привет! Я открыл твою ссылку",
                bodyHTML: "<p>Привет, это \(HomepageTemplates.escapeHTML(displayName))!</p><p>Ты прислал мне ссылку на свою страничку — заглянул, посмотрел. Мне понравилось! Теперь я тоже живу в сети. Почаще заходи ко мне на огонёк.</p><p>Твой друг.</p>",
                tag: "homepage.feedback.\(order)",
                messageCategory: "feedback",
                relatedSiteId: "homepage-su",
                timestamp: Date()
            )
        )
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
