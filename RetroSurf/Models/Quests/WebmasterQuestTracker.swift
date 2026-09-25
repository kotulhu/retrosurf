import Foundation

/// Квест «Сайт у Серёги-вебмастера» (webmaster_serega).
///
/// Игрок заказывает сайт: пишет Серёге (serega@webmaster-serega.su) на заказ,
/// Серёга присылает счёт почтой, игрок оплачивает — отправляет ему фотографию
/// квитанции (квестовый предзагруженный файл из «Мои документы»,
/// contentId `local_payment_receipt`) как вложение, — и через 15 минут Серёга
/// подтверждает готовность работы.
///
/// Флаг `quest.webmaster.done` ставится ТОЛЬКО после оплаты и задержки
/// (делается из confirmed-фазы, а не из «просто ответил»). Дальше
/// PlayerPageInstaller публикует личную страничку и выдаёт artifact.page (+20
/// очков), а ProgressStore открывает последнюю страницу на пороге 60 очков.
/// Трекер слушает только типизированный GameBus, никаких NotificationCenter.
@MainActor
final class WebmasterQuestTracker: ObservableObject {
    static let npcId = "webmaster_serega"
    static let webmasterEmail = "serega@webmaster-serega.su"
    /// Предзагруженная квитанция из «Мои документы» (preinstalled.json).
    static let receiptContentId = "local_payment_receipt"
    /// Пауза между оплатой и подтверждением готовности.
    static let confirmDelay: TimeInterval = 15 * 60

    private enum Phase {
        case idle                  // ждём почту
        case awaitingOrder         // игрок должен заказать сайт
        case awaitingPayment       // счёт выставлен, ждём квитанцию
        case awaitingConfirmation  // оплата получена, ждём подтверждение
        case completed
    }

    @Published private(set) var status = "не запущен"

    private let npcCatalog: NpcCatalog
    private let mailSite: MailSite
    private let flags: FlagStore
    private let bus: GameBus

    private var phase: Phase = .idle
    private var subscriptionID: UUID?
    private var task: Task<Void, Never>?
    private var confirmAt: Date?
    private var paymentNudged = false

    init(npcCatalog: NpcCatalog, mailSite: MailSite, flags: FlagStore, bus: GameBus) {
        self.npcCatalog = npcCatalog
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
        if flags.contains("mail.registered") {
            phase = .awaitingOrder
            status = "закажите сайт: напишите Серёге"
        }
        if flags.contains("quest.webmaster.done") {
            phase = .completed
            status = "квест завершён"
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
        confirmAt = nil
        paymentNudged = false
        status = "сброшен"
        start()
    }

    // MARK: - Bus handling

    private func handle(_ event: GameBus.Event) {
        switch event {
        case .mailSent(let mail):
            handleMailSent(mail)
        case .flagChanged(let change):
            if change.key == "mail.registered", change.value, case .idle = phase {
                phase = .awaitingOrder
                status = "закажите сайт: напишите Серёге"
            }
        case .mailReceived, .fileDownloaded, .fileAttached, .fileSent, .fileReceived,
             .fileRemoved, .artifactEarned, .loveMessageSent, .loveMessageDelivered,
             .bytesTransferred, .bytesDownloaded:
            break
        }
    }

    private func handleMailSent(_ mail: MailSentEvent) {
        let to = mail.to.trimmingCharacters(in: .whitespaces).lowercased()
        guard to == Self.webmasterEmail.lowercased() else { return }
        switch phase {
        case .awaitingOrder:
            deliverInvoice()
            phase = .awaitingPayment
            paymentNudged = false
            status = "счёт выставлен — ждём квитанцию"
            // Заказ и оплата в одном письме: сразу принимаем квитанцию.
            if mail.attachmentContentIds.contains(Self.receiptContentId) {
                confirmPayment()
            }
        case .awaitingPayment:
            if mail.attachmentContentIds.contains(Self.receiptContentId) {
                confirmPayment()
            } else {
                deliverPaymentNudge()
            }
        default:
            break
        }
    }

    // MARK: - Flow

    private func confirmPayment() {
        deliverPaidAck()
        confirmAt = Date().addingTimeInterval(Self.confirmDelay)
        phase = .awaitingConfirmation
        status = "оплата получена — сайт будет готов через 15 минут"
    }

    /// Проверка таймера: через 15 минут после оплаты — письмо о готовности
    /// и флаг quest.webmaster.done.
    func tickOnce(now: Date = Date()) {
        guard case .awaitingConfirmation = phase, let confirmAt, confirmAt <= now else { return }
        self.confirmAt = nil
        deliverConfirmation()
        flags.set("quest.webmaster.done", to: true)
        phase = .completed
        status = "работа готова — страничка опубликована"
    }

    // MARK: - Letters

    private func deliverInvoice() {
        deliver(
            subject: "Счёт на оплату — домашняя страничка",
            bodyHTML: """
            <p>{{player.username}}, привет!</p>
            <p>Заказ принял. Домашняя страничка — 1000 руб. (предоплата 50% — 500 руб.).</p>
            <p>Оплатить просто: приложите к ответному письму фотографию квитанции об оплате — она уже лежит у вас в «Мои документы» (файл «квитанция об оплате»).</p>
            <p>Как только увижу квитанцию — сразу приступаю к работе. Через 15 минут пришлю подтверждение.</p>
            <p>Серёга</p>
            """,
            tag: "quest.webmaster.invoice"
        )
    }

    private func deliverPaidAck() {
        deliver(
            subject: "Оплату видел!",
            bodyHTML: "<p>Привет!</p><p>Квитанцию увидел, спасибо. Приступаю к работе — через 15 минут пришлю подтверждение.</p><p>Серёга</p>",
            tag: "quest.webmaster.paid"
        )
    }

    private func deliverPaymentNudge() {
        guard !paymentNudged else { return }
        paymentNudged = true
        deliver(
            subject: "Жду квитанцию",
            bodyHTML: "<p>Письмо получил, но фотографию квитанции не увидел.</p><p>Приложите к письму файл «квитанция об оплате» из папки «Мои документы» — и я сразу приступаю.</p><p>Серёга</p>",
            tag: "quest.webmaster.nudge"
        )
    }

    private func deliverConfirmation() {
        deliver(
            subject: "Готово! Ваша страничка в сети",
            bodyHTML: """
            <p>{{player.username}}, готово!</p>
            <p>Ваша личная страничка открыта на {homepage.su}/p/you.html.</p>
            <p>Заходите почаще — буду добавлять гостевую книгу и счётчик посещений.</p>
            <p>Спасибо за заказ!</p>
            <p>Серёга</p>
            """,
            tag: "quest.webmaster.done"
        )
    }

    /// Отправить письмо игроку от Серёги. From — как у NPC в каталоге; inbox
    /// всегда игрока. Подстановка usernames такая же, как у NpcMessenger.
    @discardableResult
    private func deliver(subject: String, bodyHTML: String, tag: String?) -> Int {
        let npc = npcCatalog.npc(withId: Self.npcId)
        let name = npc?.displayName ?? "Серёга — веб-мастер"
        let email = npc?.email ?? Self.webmasterEmail
        var body = bodyHTML
        body = body.replacingOccurrences(of: "{{player.username}}", with: mailSite.currentUsername ?? "Ты")
        body = body.replacingOccurrences(of: "{homepage.su}", with: "http://homepage.su")
        return mailSite.deliver(
            MailDraft(
                from: "\(name) <\(email)>",
                subject: subject,
                bodyHTML: body,
                tag: tag,
                timestamp: Date(),
                folder: .inbox
            )
        )
    }

    // MARK: - Debug / test helpers

    /// Сразу выставить счёт (переход: ожидание заказа → ожидание оплаты).
    /// Возвращает false, если квест уже завершён.
    @discardableResult
    func forceStart() -> Bool {
        switch phase {
        case .completed, .awaitingPayment, .awaitingConfirmation:
            return false
        case .idle:
            phase = .awaitingOrder
        case .awaitingOrder:
            break
        }
        deliverInvoice()
        phase = .awaitingPayment
        paymentNudged = false
        status = "счёт выставлен — ждём квитанцию"
        return true
    }

    /// Для тестов: публикует «игрок отправил письмо-заказ» без вложений.
    func simulateOrder() {
        bus.publish(.mailSent(
            MailSentEvent(
                messageId: Int.random(in: 700_000...799_999),
                to: Self.webmasterEmail,
                subject: "Здравствуйте, хочу заказать сайт!",
                attachmentContentIds: [],
                tag: nil,
                sentAt: Date()
            )
        ))
    }

    /// Для тестов: публикует «игрок отправил квитанцию» Серёге.
    func simulatePayment() {
        bus.publish(.mailSent(
            MailSentEvent(
                messageId: Int.random(in: 700_000...799_999),
                to: Self.webmasterEmail,
                subject: "Оплатил! Квитанция во вложении",
                attachmentContentIds: [Self.receiptContentId],
                tag: nil,
                sentAt: Date()
            )
        ))
    }

    /// Для тестов: немедленно завершить квест (минуя 15-минутную паузу).
    func forceComplete() {
        guard case .awaitingConfirmation = phase else { return }
        confirmAt = nil
        deliverConfirmation()
        flags.set("quest.webmaster.done", to: true)
        phase = .completed
        status = "работа готова — страничка опубликована"
    }
}