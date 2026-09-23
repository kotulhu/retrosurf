import Foundation

/// Convenience for external callers so they don't construct SiteMailMessage directly.
struct MailDraft: Sendable {
    let from: String
    let subject: String
    let bodyHTML: String
    let tag: String?
    let timestamp: Date
    let folder: SiteMailMessage.Folder   // usually .inbox
    let attachments: [MailAttachment]

    init(
        from: String,
        subject: String,
        bodyHTML: String,
        tag: String?,
        timestamp: Date,
        folder: SiteMailMessage.Folder,
        attachments: [MailAttachment] = []
    ) {
        self.from = from
        self.subject = subject
        self.bodyHTML = bodyHTML
        self.tag = tag
        self.timestamp = timestamp
        self.folder = folder
        self.attachments = attachments
    }
}

@MainActor
final class MailSite: BaseInteractiveSite<MailState>, QuestLetterReceiver {
    static let host = "pochta.su"

    /// Fired when a homepage feedback letter is delivered via pochta.su.
    var onHomepageFeedbackReceived: (() -> Void)?

    private let fileStore: FileStore
    private let localFileStore: LocalFileStore
    private let bus: GameBus
    private let npcCatalog: NpcCatalog?

    init(fileStore: FileStore, localFileStore: LocalFileStore, bus: GameBus, npcCatalog: NpcCatalog? = nil) {
        self.fileStore = fileStore
        self.localFileStore = localFileStore
        self.bus = bus
        self.npcCatalog = npcCatalog
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

    override func resetGameplay() {
        state = MailState()
    }

    /// Inbox messages for SwiftUI fallbacks and debug panels.
    var inboxMessages: [SiteMailMessage] {
        state.messages
            .filter { $0.folder == .inbox }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Имя текущего зарегистрированного пользователя, если он есть.
    var currentUsername: String? {
        state.account?.username
    }

    func markRead(messageId: Int) {
        guard let index = state.messages.firstIndex(where: { $0.id == messageId }) else { return }
        state.messages[index].isRead = true
    }

    /// Deliver a letter into the player's inbox. For every attachment the
    /// delivered message carries, a FileInstance copy is created in the
    /// NPC's inbox node and `.fileReceived` is published; finally `.mailReceived`
    /// fires for the letter itself.
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
                tag: draft.tag,
                attachments: draft.attachments
            )
        )
        for attachment in draft.attachments {
            let ownerNode = npcNode(for: draft.from, messageId: id)
            let content = FileContent(
                contentId: attachment.contentId,
                name: attachment.fileName,
                sizeBytes: attachment.sizeBytes,
                hasVirus: attachment.hasVirus,
                virusKind: nil,
                sourceURL: resolve("/message/\(id)"),
                downloadedAt: draft.timestamp
            )
            let copy = fileStore.create(content: content, ownerNode: ownerNode)
            bus.publish(.fileReceived(
                FileReceivedEvent(
                    contentId: copy.content.contentId,
                    instanceId: copy.instanceId,
                    messageId: id,
                    from: draft.from
                )
            ))
        }
        bus.publish(.mailReceived(
            MailReceivedEvent(
                messageId: id,
                from: draft.from,
                subject: draft.subject,
                tag: draft.tag,
                receivedAt: draft.timestamp
            )
        ))
        return id
    }

    /// Deliver a resolved quest letter into the inbox. The visible "from" is
    /// the sender's address; everything else maps 1:1.
    @discardableResult
    func deliver(_ message: QuestMessage) -> Int {
        if message.messageCategory == "feedback" && message.relatedSiteId == "homepage-su" {
            onHomepageFeedbackReceived?()
        }
        return deliver(
            MailDraft(
                from: message.sender.address,
                subject: message.subject,
                bodyHTML: message.bodyHTML,
                tag: message.tag,
                timestamp: message.timestamp,
                folder: .inbox
            )
        )
    }

    /// Files the player can attach: the downloads and documents folders minus
    /// virus-flagged copies.
    func attachableInstances() -> [FileInstance] {
        localFileStore.attachableFiles(in: [.downloads, .documents])
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
        case .composeAttach:
            return protected { self.handleComposeAttach() }
        case .composeRemoveAttachment(_, let instanceId):
            return protected { self.handleComposeRemoveAttachment(instanceId: instanceId) }
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
            return protected { self.getCompose(url: url) }
        default:
            if path.hasPrefix("/message/") {
                var idString = String(path.dropFirst("/message/".count))
                if idString.hasSuffix("/reply") {
                    idString = String(idString.dropLast("/reply".count))
                    return protected { self.replyToMessage(idString: idString) }
                }
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
        case "/compose/attach":
            return protected { self.postComposeAttach(form: form) }
        case "/compose/addAttachment":
            return protected { self.postComposeAddAttachment(form: form) }
        case "/compose/removeAttachment":
            return protected { self.postComposeRemoveAttachment(form: form) }
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
        if state.session != nil { return redirect(to: "/inbox") }
        return redirect(to: "/login")
    }

    private func getRegister() -> SiteResponse {
        if state.account != nil { return redirect(to: "/login") }
        return page(path: "/register", title: "Регистрация", html: MailTemplates.registerPage(error: nil))
    }

    private func getLogin() -> SiteResponse {
        if state.session != nil { return redirect(to: "/inbox") }
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

    private func getCompose(url: URL) -> SiteResponse {
        guard isLoggedIn else { return redirect(to: "/login") }
        if let replyToID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name.caseInsensitiveCompare("replyTo") == .orderedSame })?.value,
           let id = Int(replyToID),
           let message = state.messages.first(where: { $0.id == id }) {
            prefillReply(from: message)
        }
        return composePage()
    }

    /// Query-free reply route: the browser never turns this into a form
    /// submission. Unknown message → plain compose, never a crash.
    private func replyToMessage(idString: String) -> SiteResponse {
        guard let id = Int(idString),
              let message = state.messages.first(where: { $0.id == id }) else {
            return redirect(to: "/compose")
        }
        prefillReply(from: message)
        return composePage()
    }

    /// Fill the compose draft for replying to a letter: recipient, RE: subject
    /// (never doubled), plain-text quoted body, no attachments.
    private func prefillReply(from message: SiteMailMessage) {
        state.composeDraft.to = extractEmail(from: message.from)
        let subject = message.subject.trimmingCharacters(in: .whitespaces)
        let alreadyPrefixed = subject.lowercased().hasPrefix("re:")
        state.composeDraft.subject = alreadyPrefixed ? subject : "RE: \(message.subject)"
        state.composeDraft.body = quoteBody(for: message)
        state.composeDraft.attachments = []
    }

    private func composePage() -> SiteResponse {
        page(
            path: "/compose",
            title: "Написать",
            html: MailTemplates.composePage(draft: state.composeDraft)
        )
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
        func g(_ key: String) -> String? {
            form[key] ?? form[key.lowercased()]
                ?? form.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        }
        if state.account != nil { return redirect(to: "/login") }
        let username = g("username")?.trimmingCharacters(in: .whitespaces) ?? ""
        let password = g("password") ?? ""
        let displayName = g("displayName")?.trimmingCharacters(in: .whitespaces) ?? ""
        let secretQuestion = g("secretQuestion") ?? ""
        let secretAnswer = g("secretAnswer")?.trimmingCharacters(in: .whitespaces) ?? ""
        print("[Debug-MailSite/postRegister] form приехала: username=", (username.isEmpty ? "<ПУСТО>" : username), " password=", (password.isEmpty ? "<ПУСТО>" : "***"), " displayName=", (displayName.isEmpty ? "<ПУСТО>" : displayName), " secretQuestion=", (secretQuestion.isEmpty ? "<ПУСТО>" : secretQuestion), " secretAnswer=", (secretAnswer.isEmpty ? "<ПУСТО>" : secretAnswer))
        guard !username.isEmpty, !password.isEmpty, !secretQuestion.isEmpty, !secretAnswer.isEmpty else {
            let errorPage = SitePage(url: resolve("/register"), title: "Регистрация", html: MailTemplates.registerPage(error: "Заполните все поля"))
            return .compound([.page(errorPage), .alert("Заполните все поля")])
        }
        guard MailTemplates.secretQuestions.contains(secretQuestion) else {
            let errorPage = SitePage(url: resolve("/register"), title: "Регистрация", html: MailTemplates.registerPage(error: "Выберите секретный вопрос из списка"))
            return .compound([.page(errorPage), .alert("Выберите секретный вопрос из списка")])
        }
        let account = MailAccount(
            username: username,
            password: password,
            displayName: displayName.isEmpty ? username : displayName,
            secretQuestion: secretQuestion,
            secretAnswer: secretAnswer,
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
        return .compound([
            .redirect(resolve("/inbox")),
            .effect(.setFlag("mail.registered", true)),
            .effect(.advanceQuest(QuestManager.registrationQuestID, "pochta-su"))
        ])
    }

    private func postLogin(_ form: [String: String]) -> SiteResponse {
        guard let account = state.account else {
            let errorPage = SitePage(url: resolve("/login"), title: "Вход", html: MailTemplates.loginPage(error: "Такого ящика нет. Зарегистрируйте новый по ссылке ниже."))
            return .compound([.page(errorPage), .alert("Такого ящика нет")])
        }
        let username = form["username"] ?? ""
        let password = form["password"] ?? ""
        guard username == account.username, password == account.password else {
            let errorPage = SitePage(url: resolve("/login"), title: "Вход", html: MailTemplates.loginPage(error: "Неверный логин или пароль"))
            return .compound([.page(errorPage), .alert("Неверный логин или пароль")])
        }
        state.session = MailSession(username: account.username, loggedInAt: Date())
        return redirect(to: "/inbox")
    }

    // MARK: - Compose attachments

    /// Open the native picker. No attachment state changes here; the form's
    /// text fields are stashed so the subsequent /compose reload restores them.
    private func handleComposeAttach() -> SiteResponse {
        .presentAttachmentPicker(attachableInstances())
    }

    /// Remove one attachment from the transient draft and return to compose.
    private func handleComposeRemoveAttachment(instanceId: String) -> SiteResponse {
        guard !instanceId.isEmpty else { return redirect(to: "/compose") }
        guard let index = state.composeDraft.attachments.firstIndex(where: { $0.instanceId == instanceId }) else {
            return redirect(to: "/compose")
        }
        _ = fileStore.remove(instanceId: instanceId)
        state.composeDraft.attachments.remove(at: index)
        return redirect(to: "/compose")
    }

    private func postComposeAttach(form: [String: String]) -> SiteResponse {
        stashDraft(form)
        return .presentAttachmentPicker(attachableInstances())
    }

    /// Appends a snapshot of the chosen download to the draft. The download in
    /// the "downloads" node is untouched — a fresh copy is created in the draft
    /// node and referenced by the new MailAttachment.
    private func postComposeAddAttachment(form: [String: String]) -> SiteResponse {
        stashDraft(form)
        let instanceId = form.first(where: { $0.key.caseInsensitiveCompare("instanceId") == .orderedSame })?.value ?? ""
        guard !instanceId.isEmpty else { return redirect(to: "/compose") }
        guard let source = fileStore.instance(withId: instanceId), !source.content.hasVirus else {
            return redirect(to: "/compose")
        }
        guard !state.composeDraft.attachments.contains(where: { $0.contentId == source.content.contentId }) else {
            return redirect(to: "/compose")
        }
        let draftId = String(UUID().uuidString.prefix(8))
        let copy = fileStore.create(content: source.content, ownerNode: "mail:draft:\(draftId)")
        state.composeDraft.attachments.append(
            MailAttachment(
                instanceId: copy.instanceId,
                contentId: copy.content.contentId,
                fileName: copy.content.name,
                sizeBytes: copy.content.sizeBytes,
                hasVirus: copy.content.hasVirus
            )
        )
        bus.publish(.fileAttached(
            FileAttachedEvent(
                contentId: copy.content.contentId,
                instanceId: copy.instanceId,
                draftId: draftId
            )
        ))
        return redirect(to: "/compose")
    }

    private func postComposeRemoveAttachment(form: [String: String]) -> SiteResponse {
        stashDraft(form)
        let instanceId = form.first(where: { $0.key.caseInsensitiveCompare("instanceId") == .orderedSame })?.value ?? ""
        guard !instanceId.isEmpty else { return redirect(to: "/compose") }
        guard let index = state.composeDraft.attachments.firstIndex(where: { $0.instanceId == instanceId }) else {
            return redirect(to: "/compose")
        }
        _ = fileStore.remove(instanceId: instanceId)
        state.composeDraft.attachments.remove(at: index)
        return redirect(to: "/compose")
    }

    /// Keep the to/subject/body the player already typed across attach/remove.
    /// Only keys actually present in the form are updated, so a submission
    /// that carries just an instanceId (add/remove attachment) never wipes
    /// the fields that are already resting in the draft.
    private func stashDraft(_ form: [String: String]) {
        func read(_ key: String) -> String? {
            form[key] ?? form.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        }
        if let to = read("to") { state.composeDraft.to = to.trimmingCharacters(in: .whitespaces) }
        if let subject = read("subject") { state.composeDraft.subject = subject.trimmingCharacters(in: .whitespaces) }
        if let body = read("body") { state.composeDraft.body = body }
    }

    private func postCompose(form: [String: String]) -> SiteResponse {
        guard let account = state.account else { return redirect(to: "/login") }
        let to = (form["to"] ?? "").trimmingCharacters(in: .whitespaces)
        let subject = (form["subject"] ?? "").trimmingCharacters(in: .whitespaces)
        let body = form["body"] ?? ""
        // Plain text from the textarea goes to HTML like every other message:
        // wrapped in <p>, newlines become <br>. No escaping here — the value
        // already came from a textarea that was escaped on render.
        let bodyHTML = "<p>" + body.replacingOccurrences(of: "\n", with: "<br>") + "</p>"

        // Attachments come from the persisted draft (which survives the
        // to/subject/body round-trips), not from hidden form fields.
        let attachments = state.composeDraft.attachments

        let message = SiteMailMessage(
            id: state.nextMessageId,
            from: "\(account.username)@\(Self.host)",
            to: to,
            subject: subject.isEmpty ? "(без темы)" : subject,
            bodyHTML: bodyHTML,
            timestamp: Date(),
            isRead: true,
            folder: .sent,
            tag: nil,
            attachments: attachments
        )
        state.nextMessageId += 1
        state.messages.append(message)

        for attachment in attachments {
            if let moved = fileStore.move(instanceId: attachment.instanceId, toNode: "mail:sent:\(message.id)") {
                bus.publish(.fileSent(
                    FileSentEvent(
                        contentId: moved.content.contentId,
                        instanceId: moved.instanceId,
                        messageId: message.id,
                        to: to
                    )
                ))
            }
        }
        bus.publish(.mailSent(
            MailSentEvent(
                messageId: message.id,
                to: to,
                subject: message.subject,
                attachmentContentIds: attachments.map(\.contentId),
                tag: nil,
                sentAt: Date()
            )
        ))

        state.composeDraft = ComposeDraft()
        return redirect(to: "/sent")
    }

    // MARK: - Helpers

    /// The NPC inbox node for a delivered letter: "npc:{npcId}:inbox:{id}".
    /// Unknown senders get a generic inbox node; nothing here can crash.
    private func npcNode(for from: String, messageId: Int) -> String {
        let npcId = npcCatalog?.npc(withEmail: emailAddress(from: from))?.id ?? "unknown"
        return "npc:\(npcId):inbox:\(messageId)"
    }

    /// Strip a display name from a "Серёга <serega@pochta.su>" string.
    private func emailAddress(from raw: String) -> String {
        if let start = raw.firstIndex(of: "<"), let end = raw.lastIndex(of: ">"), start < end {
            return String(raw[raw.index(after: start)..<end])
        }
        return raw
    }

    /// "Имя <email>" -> "email". If there are no angle brackets, the trimmed
    /// input is returned unchanged.
    private func extractEmail(from: String) -> String {
        if let start = from.firstIndex(of: "<"), let end = from.lastIndex(of: ">"), start < end {
            return String(from[from.index(after: start)..<end])
        }
        return from.trimmingCharacters(in: .whitespaces)
    }

    /// 90s-style reply quote as plain text:
    /// "\n\n---\nИмя <email> пишет (14.03.1999 15:42):\n> строка 1\n> строка 2"
    /// HTML in the original body is reduced to plain text and long lines are
    /// wrapped at word boundaries (max 200 chars per line).
    private func quoteBody(for message: SiteMailMessage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let stamp = formatter.string(from: message.timestamp)
        let plain = plainText(fromHTML: message.bodyHTML)
        let wrapped = wrapQuoted(plain, at: 200)
        var result = "\n\n---\n"
        result += "\(message.from) пишет (\(stamp)):\n"
        result += wrapped.map { "> \($0)" }.joined(separator: "\n")
        return result
    }

    /// Simple tag stripper: <p>/<br> become newlines, the rest of <...> is
    /// removed, and HTML entities are decoded.
    private func plainText(fromHTML html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        while let open = text.firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            text.removeSubrange(open...close)
        }
        let entities = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")
        ]
        for (from, to) in entities {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }

    /// Wrap lines longer than `width` at word boundaries.
    private func wrapQuoted(_ text: String, at width: Int) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            if paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
                continue
            }
            let words = paragraph.split(separator: " ").map(String.init)
            var current = ""
            for word in words {
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= width {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = word
                }
            }
            lines.append(current)
        }
        return lines
    }

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