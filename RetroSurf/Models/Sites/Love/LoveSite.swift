import Foundation

/// Интерактивный сайт знакомств love.su: анкеты, страница профиля и
/// внутренняя переписка («Переписка» в меню + кнопка на анкете). Анкеты
/// целиком из profiles.json (LoveContent); внутренний чат-тред — архивное
/// состояние LoveState. Ответы NPC приходят через `pendingChatReplies` с
/// задержкой 3–10 с (похоже на почту, но заметно быстрее).
@MainActor
final class LoveSite: BaseInteractiveSite<LoveState> {
    static let host = "love.su"

    private let content: LoveContent
    private let fileStore: FileStore
    private let localFileStore: LocalFileStore
    private let bus: GameBus

    init(
        content: LoveContent,
        fileStore: FileStore,
        localFileStore: LocalFileStore,
        bus: GameBus
    ) {
        self.content = content
        self.fileStore = fileStore
        self.localFileStore = localFileStore
        self.bus = bus
        super.init(
            descriptor: SiteDescriptor(
                id: "love",
                host: Self.host,
                displayName: "love.su — знакомства",
                iconSystemName: "heart"
            ),
            initialState: LoveState()
        )
    }

    override func resetGameplay() {
        state = LoveState()
    }

    // MARK: - Request handling

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        deliverDueReplies()
        switch request {
        case .open(let url):
            return handleGet(url)
        case .submit(let url, let form):
            return handlePost(url, form: form)
        case .invoke(let action, _):
            return .failure("404: \(action)")
        case .composeAttach(_), .composeRemoveAttachment(_, _):
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
        case "/mail": return mailPage()
        default:
            if path.hasPrefix("/profile/") {
                return profilePage(String(path.dropFirst("/profile/".count)))
            }
            if path.hasPrefix("/mail/") {
                return threadPage(String(path.dropFirst("/mail/".count)))
            }
            return .failure("404: \(path)")
        }
    }

    private func handlePost(_ url: URL, form: [String: String]) -> SiteResponse {
        guard let host = url.host?.lowercased(), host == Self.host else {
            return .failure("Host not found: \(url.host ?? url.absoluteString)")
        }
        let path = url.path.isEmpty ? "/" : url.path
        switch path {
        case "/mail/send":
            return postSend(form)
        default:
            return .failure("404: \(path)")
        }
    }

    // MARK: - Pages

    private func indexPage() -> SiteResponse {
        let body = LoveTemplates.indexBody(content: content)
        return .page(SitePage(
            url: resolve("/"),
            title: content.site.title,
            html: LoveTemplates.fullHTML(
                site: content.site,
                title: content.site.title,
                body: body,
                active: "index",
                unreadCount: totalUnread
            )
        ))
    }

    private func aboutPage() -> SiteResponse {
        let body = LoveTemplates.aboutBody(content: content)
        return .page(SitePage(
            url: resolve("/about"),
            title: "О сайте",
            html: LoveTemplates.fullHTML(
                site: content.site,
                title: "О сайте",
                body: body,
                active: "about",
                unreadCount: totalUnread
            )
        ))
    }

    private func profilePage(_ profileID: String) -> SiteResponse {
        guard let profile = content.profile(id: profileID) else {
            return .failure("404: /profile/\(profileID)")
        }
        state.visitedProfileIDs.insert(profileID)
        let body = LoveTemplates.profileBody(profile: profile)
        return .page(SitePage(
            url: resolve("/profile/\(profileID)"),
            title: profile.nickname,
            html: LoveTemplates.fullHTML(
                site: content.site,
                title: "Анкета: \(profile.nickname)",
                body: body,
                active: "index",
                unreadCount: totalUnread
            )
        ))
    }

    /// Список диалогов внутренней переписки: профиль, последнее сообщение,
    /// количество непрочитанных. Треды без единого сообщения не показываются.
    private func mailPage() -> SiteResponse {
        let threads = activeThreads()
        let body = LoveTemplates.mailBody(
            threads: threads.map {
                LoveTemplates.ThreadSummary(
                    id: $0.id,
                    nickname: $0.nickname,
                    age: $0.age,
                    lastMessage: $0.lastMessage,
                    lastTimestamp: $0.lastTimestamp,
                    unreadCount: unreadCount(for: $0.id)
                )
            }
        )
        return .page(SitePage(
            url: resolve("/mail"),
            title: "Переписка",
            html: LoveTemplates.fullHTML(
                site: content.site,
                title: "Переписка",
                body: body,
                active: "mail",
                unreadCount: totalUnread
            )
        ))
    }

    /// Тред с профилем: вся история сообщений + форма ответа.
    private func threadPage(_ profileID: String) -> SiteResponse {
        guard let profile = content.profile(id: profileID) else {
            return .failure("404: /mail/\(profileID)")
        }
        markThreadRead(profileID)
        let messages = thread(profileID).messages.sorted { $0.id < $1.id }
        let drafts = state.drafts[profileID]
        let body = LoveTemplates.threadBody(
            profile: profile,
            messages: messages,
            attachmentName: drafts?.attachmentName,
            attachableFiles: attachableFiles()
        )
        return .page(SitePage(
            url: resolve("/mail/\(profileID)"),
            title: "Переписка: \(profile.nickname)",
            html: LoveTemplates.fullHTML(
                site: content.site,
                title: "Переписка: \(profile.nickname)",
                body: body,
                active: "mail",
                unreadCount: totalUnread
            )
        ))
    }

    // MARK: - POST: отправка сообщения

    private func postSend(_ form: [String: String]) -> SiteResponse {
        func g(_ key: String) -> String? {
            form[key] ?? form.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        }
        let profileID = g("profileID") ?? ""
        guard let profile = content.profile(id: profileID) else {
            return .failure("Profile not found")
        }
        let text = g("text") ?? ""
        let attachmentInstanceID = g("attachment") ?? ""
        let attachmentName = resolveAttachmentName(instanceID: attachmentInstanceID)

        let messageID = state.nextMessageID
        state.nextMessageID += 1
        var thread = self.thread(profileID)
        thread.messages.append(LoveState.ChatMessage(
            id: messageID,
            sender: .player,
            textHTML: "<p>" + text.replacingOccurrences(of: "\n", with: "<br>") + "</p>",
            timestamp: Date(),
            attachmentName: attachmentName,
            isRead: true
        ))
        state.threads[profileID] = thread
        state.drafts[profileID] = LoveState.ChatDraft(text: "", attachmentName: nil)

        var attachmentContentIds: [String] = []
        if let instanceID = g("attachment"),
           let source = fileStore.instance(withId: instanceID), !source.content.hasVirus {
            // Копия во вложении «уходит» NPC в её узел, как в pochta.su.
            let copy = fileStore.create(
                content: source.content,
                ownerNode: "love:npc:\(profileID):msg:\(messageID)"
            )
            attachmentContentIds = [copy.content.contentId]
        }

        bus.publish(.loveMessageSent(
            LoveMessageSentEvent(
                messageId: messageID,
                profileID: profileID,
                body: text,
                attachmentContentIds: attachmentContentIds,
                sentAt: Date()
            )
        ))
        return redirect(to: "/mail/\(profileID)")
    }

    // MARK: - NPC replies (внутренняя переписка)

    /// Запланировать ответ NPC в тред профиля с задержкой `delay` секунд
    /// (похоже на почту, но с коротким ожиданием — 3–10 с).
    @discardableResult
    func scheduleNpcReply(
        profileID: String,
        textHTML: String,
        attachmentName: String? = nil,
        delay: TimeInterval,
        tag: String? = nil
    ) -> Bool {
        guard content.profile(id: profileID) != nil else { return false }
        state.pendingChatReplies.append(LoveState.PendingChatReply(
            profileID: profileID,
            textHTML: textHTML,
            attachmentName: attachmentName,
            deliverAt: Date().addingTimeInterval(delay),
            tag: tag
        ))
        return true
    }

    /// Перенести созревшие ответы NPC в треды (непрочитанными). Вызывается
    /// на каждом запросе страницы — ответ «приходит» при следующем обновлении.
    func deliverDueReplies(now: Date = Date()) {
        let due = state.pendingChatReplies
            .filter { $0.deliverAt <= now }
            .sorted { $0.deliverAt < $1.deliverAt }
        guard !due.isEmpty else { return }
        for reply in due {
            let messageID = state.nextMessageID
            state.nextMessageID += 1
            var thread = self.thread(reply.profileID)
            thread.messages.append(LoveState.ChatMessage(
                id: messageID,
                sender: .npc,
                textHTML: reply.textHTML,
                timestamp: reply.deliverAt,
                attachmentName: reply.attachmentName,
                isRead: false
            ))
            state.threads[reply.profileID] = thread
        }
        let dueTags = due.compactMap(\.tag)
        state.pendingChatReplies.removeAll { $0.deliverAt <= now }
        if !dueTags.isEmpty {
            bus.publish(.loveMessageDelivered(dueTags))
        }
    }

    /// Имя файла по выбранному instanceId, или nil если выбор пуст.
    private func resolveAttachmentName(instanceID: String) -> String? {
        guard !instanceID.isEmpty, let instance = fileStore.instance(withId: instanceID),
              !instance.content.hasVirus else { return nil }
        return instance.content.name
    }

    // MARK: - State helpers

    private func thread(_ profileID: String) -> LoveState.ChatThread {
        state.threads[profileID] ?? LoveState.ChatThread()
    }

    private func unreadCount(for profileID: String) -> Int {
        thread(profileID).messages.filter { $0.sender == .npc && !$0.isRead }.count
    }

    private var totalUnread: Int {
        state.threads.values
            .flatMap(\.messages)
            .filter { $0.sender == .npc && !$0.isRead }
            .count
    }

    private func markThreadRead(_ profileID: String) {
        guard var thread = state.threads[profileID] else { return }
        for index in thread.messages.indices where thread.messages[index].sender == .npc {
            thread.messages[index].isRead = true
        }
        state.threads[profileID] = thread
    }

    private struct ThreadInfo {
        let id: String
        let nickname: String
        let age: Int
        let lastMessage: String
        let lastTimestamp: Date
    }

    /// Все треды с хотя бы одним сообщением, последняя активность сверху.
    private func activeThreads() -> [ThreadInfo] {
        var infos: [ThreadInfo] = []
        for (profileID, thread) in state.threads {
            guard let profile = content.profile(id: profileID), let last = thread.messages.last else { continue }
            infos.append(ThreadInfo(
                id: profileID,
                nickname: profile.nickname,
                age: profile.age,
                lastMessage: LoveTemplates.plainText(fromHTML: last.textHTML),
                lastTimestamp: last.timestamp
            ))
        }
        return infos.sorted { $0.lastTimestamp > $1.lastTimestamp }
    }

    private func attachableFiles() -> [FileInstance] {
        localFileStore.attachableFiles(in: [.downloads, .documents])
    }

    // MARK: - Helpers

    private func redirect(to path: String) -> SiteResponse {
        .redirect(resolve(path))
    }

    private func resolve(_ path: String) -> URL {
        URL(string: "http://\(Self.host)\(path)")!
    }
}