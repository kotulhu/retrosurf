import Foundation

/// Convenience for external callers so they don't construct SiteMailMessage directly.
struct MailDraft: Sendable {
    let from: String
    let subject: String
    let bodyHTML: String
    let tag: String?
    let timestamp: Date
    let folder: SiteMailMessage.Folder   // usually .inbox
}

@MainActor
final class MailSite: BaseInteractiveSite<MailState> {
    static let host = "pochta.su"

    init() {
        super.init(
            descriptor: SiteDescriptor(
                id: "mail",
                host: Self.host,
                displayName: "Почта.SU",
                iconSystemName: "envelope"
            ),
            initialState: MailState()
        )
    }

    /// Inject a message from the game layer (quest letters, spam, notifications).
    /// Assigns id automatically. Returns the assigned id.
    /// Works before registration — the message sits in inbox and becomes
    /// visible once the player logs in.
    @discardableResult
    func deliver(_ draft: MailDraft) -> Int {
        let id = state.nextMessageId
        state.nextMessageId += 1
        let recipient = state.account.map { "\($0.username)@\(Self.host)" } ?? "вы@\(Self.host)"
        state.messages.append(
            SiteMailMessage(
                id: id,
                from: draft.from,
                to: recipient,
                subject: draft.subject,
                bodyHTML: draft.bodyHTML,
                timestamp: draft.timestamp,
                isRead: false,
                folder: draft.folder,
                tag: draft.tag
            )
        )
        return id
    }

    private var isLoggedIn: Bool { state.session != nil }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url):
            return handleGet(url)
        case .submit(let url, let form):
            return handlePost(url, form: form)
        case .invoke(let action, _):
            return .failure("404: \(action)")
        }
    }

    // MARK: - Routing

    private func handleGet(_ url: URL) -> SiteResponse {
        let path: String
        if let host = url.host?.lowercased(), host == Self.host {
            path = url.path.isEmpty ? "/" : url.path
        } else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        switch path {
        case "/":
            return getHome()
        case "/register":
            return getRegister()
        case "/login":
            return getLogin()
        case "/logout":
            return protected { self.logout() }
        case "/inbox":
            return protected { self.getInbox() }
        case "/sent":
            return protected { self.getSent() }
        case "/compose":
            return protected { self.getCompose() }
        default:
            if path.hasPrefix("/message/") {
                let idString = String(path.dropFirst("/message/".count))
                return protected { self.getMessage(idString: idString) }
            }
            return .failure("404: \(path)")
        }
    }

    private func handlePost(_ url: URL, form: [String: String]) -> SiteResponse {
        let path: String
        if let host = url.host?.lowercased(), host == Self.host {
            path = url.path.isEmpty ? "/" : url.path
        } else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        switch path {
        case "/register":
            return postRegister(form)
        case "/login":
            return postLogin(form)
        case "/compose":
            return protected { self.postCompose(form: form) }
        default:
            return .failure("404: \(path)")
        }
    }

    /// Protected routes redirect to /login when the player isn't logged in —
    /// never a .failure, never an error page.
    private func protected(_ body: () -> SiteResponse) -> SiteResponse {
        guard isLoggedIn else { return redirect(to: "/login") }
        return body()
    }

    // MARK: - GET

    private func getHome() -> SiteResponse {
        if state.account == nil { return redirect(to: "/register") }
        if state.session == nil { return redirect(to: "/login") }
        return redirect(to: "/inbox")
    }

    private func getRegister() -> SiteResponse {
        if state.account != nil { return redirect(to: "/login") }
        return page(path: "/register", title: "Регистрация", html: MailTemplates.registerPage(error: nil))
    }

    private func getLogin() -> SiteResponse {
        if state.account == nil { return redirect(to: "/register") }
        return page(path: "/login", title: "Вход", html: MailTemplates.loginPage(error: nil))
    }

    private func logout() -> SiteResponse {
        state.session = nil
        return redirect(to: "/login")
    }

    private func getInbox() -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/login") }
        return page(path: "/inbox", title: "Входящие", html: MailTemplates.inboxPage(messages: state.messages, account: account))
    }

    private func getSent() -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/login") }
        return page(path: "/sent", title: "Отправленные", html: MailTemplates.sentPage(messages: state.messages, account: account))
    }

    private func getCompose() -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/login") }
        return page(path: "/compose", title: "Написать", html: MailTemplates.composePage(account: account))
    }

    private func getMessage(idString: String) -> SiteResponse {
        guard let id = Int(idString),
              let index = state.messages.firstIndex(where: { $0.id == id }) else {
            return .failure("Message not found")
        }
        let wasUnread = !state.messages[index].isRead
        if wasUnread {
            state.messages[index].isRead = true
        }
        guard let account = state.account else { return redirect(to: "/login") }
        let message = state.messages[index]
        let page = SitePage(
            url: resolve("/message/\(id)"),
            title: "Письмо",
            html: MailTemplates.letterPage(message: message, account: account)
        )
        if wasUnread, let tag = message.tag {
            return .compound([.page(page), .effect(.setFlag("mail.read.\(tag)", true))])
        }
        return .page(page)
    }

    // MARK: - POST

    private func postRegister(_ form: [String: String]) -> SiteResponse {
        if state.account != nil { return redirect(to: "/login") }
        let username = form["username"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let password = form["password"] ?? ""
        let displayName = form["displayName"]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            let errorPage = SitePage(url: resolve("/register"), title: "Регистрация", html: MailTemplates.registerPage(error: "Заполните все поля"))
            return .compound([.page(errorPage), .alert("Заполните все поля")])
        }
        let account = MailAccount(
            username: username,
            password: password,
            displayName: displayName.isEmpty ? username : displayName,
            createdAt: Date()
        )
        state.account = account
        state.session = MailSession(username: account.username, loggedInAt: Date())

        deliver(
            MailDraft(
                from: "admin@\(Self.host)",
                subject: "Добро пожаловать в Pochta.su",
                bodyHTML: "<p>Добро пожаловать, <b>\(MailTemplates.escapeHTML(account.displayName))</b>!</p><p>Ваш адрес: <b>\(MailTemplates.escapeHTML(account.username))@pochta.su</b>.</p><p>Вся сеть, кроме нас, ещё не готова. Но вы уже здесь.</p>",
                tag: "welcome",
                timestamp: Date(),
                folder: .inbox
            )
        )
        return .compound([.redirect(resolve("/inbox")), .effect(.setFlag("mail.registered", true))])
    }

    private func postLogin(_ form: [String: String]) -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/register") }
        let username = form["username"] ?? ""
        let password = form["password"] ?? ""
        guard username == account.username, password == account.password else {
            let errorPage = SitePage(url: resolve("/login"), title: "Вход", html: MailTemplates.loginPage(error: "Неверный логин или пароль"))
            return .compound([.page(errorPage), .alert("Неверный логин или пароль")])
        }
        state.session = MailSession(username: account.username, loggedInAt: Date())
        return redirect(to: "/inbox")
    }

    private func postCompose(form: [String: String]) -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/login") }
        let to = (form["to"] ?? "").trimmingCharacters(in: .whitespaces)
        let subject = (form["subject"] ?? "").trimmingCharacters(in: .whitespaces)
        let body = form["body"] ?? ""
        let bodyHTML = MailTemplates.escapeHTML(body).replacingOccurrences(of: "\n", with: "<br>")
        state.messages.append(
            SiteMailMessage(
                id: state.nextMessageId,
                from: "\(account.username)@\(Self.host)",
                to: to,
                subject: subject.isEmpty ? "(без темы)" : subject,
                bodyHTML: bodyHTML,
                timestamp: Date(),
                isRead: true,
                folder: .sent,
                tag: nil
            )
        )
        state.nextMessageId += 1
        return redirect(to: "/sent")
    }

    // MARK: - Helpers

    private func redirect(to path: String) -> SiteResponse {
        .redirect(resolve(path))
    }

    private func page(path: String, title: String, html: String) -> SiteResponse {
        .page(SitePage(url: resolve(path), title: title, html: html))
    }

    private func resolve(_ path: String) -> URL {
        URL(string: "http://\(Self.host)\(path)")!
    }
}