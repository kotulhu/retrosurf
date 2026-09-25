import Foundation

/// Квест «Любовь» на love.su. Трекер ждёт регистрации почты
/// (флаг `mail.registered`), после случайной задержки выбирает случайный
/// женский профиль как симпатию и ведёт переписку через ВНУТРЕННИЙ чат
/// love.su (не pochta.su!) — ответы приходят скриптом со сдвигом 3–10 с.
///
/// Логика по спецификации Part 8 (переведена на внутренний мессенджер):
///  - mail.registered → через случайные 30–120 с выбирается симпатия;
///  - симпатия сама открывает переписку через 3–10 с (opening);
///  - первое сообщение игрока симпатии → firstReply через 3–10 с;
///  - второе сообщение → secondReply + attachmentRequest (флаг quest.love.correspondence);
///  - сообщение со вложением после запроса → thanksForAttachment,
///    флаг quest.love.done + артефакт artifact.love (artifactEarned);
///  - остальным профилям → короткие случайные реплики из пула (3–10 с);
///  - любые прочие события игнорируются, трекер никогда не падает.
@MainActor
final class LoveQuestTracker: ObservableObject {
    private enum Phase {
        case idle          // игра ещё не дала разрешение
        case waitingBegin  // mail.registered есть, ждём beginAt
        case awaitingOpen  // симпатия выбрана, ждём доставку opening
        case awaitingFirst  // opening дошёл, ждём первое сообщение игрока
        case firstReplyPending  // первое сообщение получено, ждём firstReply
        case awaitingSecond     // firstReply доставлен, ждём второе сообщение
        case secondReplyPending // второе сообщение получено, ждём secondReply + attachmentRequest
        case awaitingAttachment // запрос вложения доставлен, ждём сообщение со вложением
        case completed
    }

    @Published private(set) var status: String = "не запущен"

    private let content: LoveContent
    private let replies: LoveRepliesCatalog?
    private let loveSite: LoveSite
    private let mailSite: MailSite
    private let flags: FlagStore
    private let bus: GameBus

    private var phase: Phase = .idle
    private var subscriptionID: UUID?
    private var task: Task<Void, Never>?
    private var sympathy: LoveContent.Profile?
    private var beginAt: Date?
    private var playerMessageCount = 0

    init(
        content: LoveContent,
        replies: LoveRepliesCatalog?,
        loveSite: LoveSite,
        mailSite: MailSite,
        flags: FlagStore,
        bus: GameBus
    ) {
        self.content = content
        self.replies = replies
        self.loveSite = loveSite
        self.mailSite = mailSite
        self.flags = flags
        self.bus = bus
    }

    // MARK: - Lifecycle

    func start() {
        guard subscriptionID == nil else { return }
        subscriptionID = bus.subscribe { [weak self] event in
            self?.handle(event)
        }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tickOnce()
            }
        }
        status = "ждёт регистрации почты"
        // Если почта уже зарегистрирована — стартуем задержку немедленно.
        if flags.contains("mail.registered") {
            scheduleBegin()
        }
    }

    func stop() {
        if let id = subscriptionID {
            bus.unsubscribe(id)
            subscriptionID = nil
        }
        task?.cancel()
        task = nil
    }

    func reset() {
        stop()
        phase = .idle
        sympathy = nil
        beginAt = nil
        playerMessageCount = 0
        status = "сброшен"
        start()
    }

    // MARK: - Bus handling

    private func handle(_ event: GameBus.Event) {
        switch event {
        case .flagChanged(let change):
            if change.key == "mail.registered", change.value {
                scheduleBegin()
            }
        case .loveMessageSent(let message):
            handlePlayerMessage(message)
        case .loveMessageDelivered(let tags):
            handleDelivered(tags)
        case .fileDownloaded, .fileAttached, .fileSent, .fileReceived, .fileRemoved,
             .mailSent, .mailReceived, .artifactEarned,
             .bytesTransferred, .bytesDownloaded:
            break
        }
    }

    private func scheduleBegin() {
        guard case .idle = phase else { return }
        beginAt = Date().addingTimeInterval(Double.random(in: 30...120))
        phase = .waitingBegin
        status = "симпатия появится через \(Int(beginAt!.timeIntervalSinceNow)) с"
    }

    /// Периодический тик: поджигает beginAt (симпатия пишет первой).
    func tickOnce(now: Date = Date()) {
        guard case .waitingBegin = phase, let beginAt, beginAt <= now else { return }
        guard let profile = content.profiles.randomElement() else {
            phase = .idle
            status = "нет анкет — квест невозможен"
            return
        }
        sympathy = profile
        self.beginAt = nil
        phase = .awaitingOpen
        status = "симпатия: \(profile.nickname) — она пишет первой"
        scheduleNpc(
            profileID: profile.id,
            body: replies?.opening.bodyHTML ?? "",
            tag: "quest.love.opening"
        )
    }

    // MARK: - Player messages

    private func handlePlayerMessage(_ message: LoveMessageSentEvent) {
        guard content.profile(id: message.profileID) != nil else { return }
        // Симпатия: скриптовая переписка до завершения квеста.
        if let sympathy, message.profileID == sympathy.id, case .completed = phase {
            return
        }
        if let sympathy, message.profileID == sympathy.id {
            handleSympathyMessage(message, sympathy: sympathy)
            return
        }
        // Остальные профили: случайная короткая реплика из пула.
        sendPoolReply(profileID: message.profileID)
    }

    private func handleSympathyMessage(_ message: LoveMessageSentEvent, sympathy: LoveContent.Profile) {
        switch phase {
        case .awaitingFirst, .awaitingSecond, .firstReplyPending:
            break
        case .idle, .waitingBegin, .awaitingOpen, .secondReplyPending,
             .awaitingAttachment, .completed:
            return
        }
        playerMessageCount += 1
        if attachmentRequestDelivered, !message.attachmentContentIds.isEmpty {
            phase = .awaitingAttachment
            status = "вложение дошло — скоро «Спасибо»"
            scheduleNpc(
                profileID: sympathy.id,
                body: replies?.thanksForAttachment.bodyHTML ?? "",
                tag: "quest.love.thanksForAttachment"
            )
            return
        }
        if playerMessageCount == 1 {
            phase = .firstReplyPending
            status = "первое сообщение получено, отвечу через пару секунд"
            scheduleNpc(
                profileID: sympathy.id,
                body: replies?.firstReply.bodyHTML ?? "",
                tag: "quest.love.firstReply"
            )
        } else if playerMessageCount >= 2 {
            phase = .secondReplyPending
            status = "второе сообщение получено, скоро спрошу про файл"
            scheduleNpc(
                profileID: sympathy.id,
                body: replies?.secondReply.bodyHTML ?? "",
                tag: "quest.love.secondReply"
            )
            scheduleNpc(
                profileID: sympathy.id,
                body: replies?.attachmentRequest.bodyHTML ?? "",
                tag: "quest.love.attachmentRequest"
            )
        }
    }

    private var attachmentRequestDelivered = false

    /// Случайная реплика из пула любому профилю. Всегда безопасно: пусто —
    /// просто тишина.
    private func sendPoolReply(profileID: String) {
        guard let pool = replies?.pool, !pool.isEmpty else { return }
        let reply = pool.randomElement()!
        scheduleNpc(profileID: profileID, body: reply.bodyHTML, tag: nil)
    }

    // MARK: - Delivered tags

    /// NPC-ответ стал видимым в треде — здесь трекер двигает фазу квеста.
    private func handleDelivered(_ tags: [String]) {
        switch phase {
        case .awaitingOpen where tags.contains("quest.love.opening"):
            phase = .awaitingFirst
            status = "симпатия написала первой, жду ответ"
        case .firstReplyPending where tags.contains("quest.love.firstReply"):
            phase = .awaitingSecond
            status = "firstReply доставлен, жду ответа"
        case .secondReplyPending where tags.contains("quest.love.secondReply"):
            flags.set("quest.love.correspondence", to: true)
            attachmentRequestDelivered = true
            phase = .awaitingAttachment
            status = "прошу прислать файл, жду вложение"
        case .awaitingAttachment where tags.contains("quest.love.thanksForAttachment"):
            complete()
        default:
            break
        }
    }

    private func complete() {
        flags.set("quest.love.done", to: true)
        if !flags.contains("artifact.love") {
            bus.publish(.artifactEarned(ArtifactEarnedEvent(artifactId: "artifact.love")))
        }
        phase = .completed
        status = "артефакт artifact.love получен"
    }

    // MARK: - NPC scheduling

    /// Запланировать сообщение NPC во внутреннем чате со сдвигом 3–10 с.
    private func scheduleNpc(profileID: String, body: String, tag: String?) {
        let resolved = body.replacingOccurrences(
            of: "{{player.username}}",
            with: mailSite.currentUsername ?? "Ты"
        )
        loveSite.scheduleNpcReply(
            profileID: profileID,
            textHTML: resolved,
            delay: Double.random(in: 3...10),
            tag: tag
        )
    }

    // MARK: - Debug / test helpers

    /// Немедленно выбрать симпатию и перейти к её открывающему сообщению.
    /// Задержка регистрации и случайный выбор пропускаются.
    @discardableResult
    func forceStart(sympathyFor profileID: String) -> Bool {
        guard let profile = content.profile(id: profileID) else {
            print("[LoveQuestTracker] forceStart: unknown profile \(profileID)")
            return false
        }
        if case .completed = phase { return false }
        sympathy = profile
        beginAt = nil
        playerMessageCount = 0
        attachmentRequestDelivered = false
        phase = .awaitingOpen
        status = "симпатия: \(profile.nickname) — она пишет первой"
        scheduleNpc(profileID: profile.id, body: replies?.opening.bodyHTML ?? "", tag: "quest.love.opening")
        return true
    }

    /// Для тестов: публикует событие «игрок написал» симпатии (без вложения).
    func simulatePlayerReply(to profileID: String, body: String = "simulated reply") {
        bus.publish(.loveMessageSent(
            LoveMessageSentEvent(
                messageId: Int.random(in: 900_000...999_999),
                profileID: profileID,
                body: body,
                attachmentContentIds: [],
                sentAt: Date()
            )
        ))
    }

    /// Для тестов: публикует событие «игрок отправил сообщение со вложением» симпатии.
    func simulateAttachmentSent(to profileID: String, contentId: String) {
        bus.publish(.loveMessageSent(
            LoveMessageSentEvent(
                messageId: Int.random(in: 900_000...999_999),
                profileID: profileID,
                body: "Файл для тебя",
                attachmentContentIds: [contentId],
                sentAt: Date()
            )
        ))
    }
}