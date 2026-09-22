import Combine
import Foundation

/// Раздаёт атмосферные письма (спам) в почту через MailSite.deliver(_:).
/// Таймерный режим — одно письмо за интервал; также есть ручные методы
/// для «мгновенной» доставки из легаси-вызовов (deliverAtmosphereMail)
/// и отладочного меню. Пустой каталог и неизвестный id не роняют генератор.
@MainActor
final class AmbientMailGenerator: ObservableObject {
    @Published private(set) var lastDeliveryAt: Date?

    private let catalog: AmbientCatalog
    private let mailSite: MailSite
    private let tickInterval: TimeInterval
    private let deliveryRange: ClosedRange<TimeInterval>

    private var task: Task<Void, Never>?
    private var nextDeliveryAt: Date?

    init(
        catalog: AmbientCatalog,
        mailSite: MailSite,
        tickInterval: TimeInterval = 30,
        deliveryRange: ClosedRange<TimeInterval> = 60...300
    ) {
        self.catalog = catalog
        self.mailSite = mailSite
        self.tickInterval = tickInterval
        self.deliveryRange = deliveryRange
    }

    /// Запускает цикл: каждые `tickInterval` секунд — оценка `tickOnce`.
    /// Идемпотентен, уважает отмену.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.tickOnce()
            }
        }
    }

    /// Останавливает цикл. Безопасен в любом порядке и в любое время.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Один проход оценки таймера. Возвращает id доставленного шаблона
    /// или nil (ждать ещё / пустой каталог).
    @discardableResult
    func tickOnce(now: Date = Date()) -> String? {
        if nextDeliveryAt == nil {
            nextDeliveryAt = now.addingTimeInterval(randomInterval())
            return nil
        }
        guard now >= (nextDeliveryAt ?? .distantFuture) else { return nil }
        guard let template = weightedRandomTemplate() else { return nil }
        mailSite.deliver(makeDraft(for: template))
        lastDeliveryAt = now
        nextDeliveryAt = now.addingTimeInterval(randomInterval())
        return template.id
    }

    /// Мгновенно доставляет один случайный шаблон, игнорируя таймер.
    /// Используется легаси-вызовом `deliverAtmosphereMail()`.
    @discardableResult
    func forceRandom() -> String? {
        guard let template = weightedRandomTemplate() else { return nil }
        mailSite.deliver(makeDraft(for: template))
        return template.id
    }

    /// Доставляет конкретный шаблон по id, игнорируя таймер.
    /// Неизвестный id → false.
    @discardableResult
    func forceDeliver(_ templateId: String) -> Bool {
        guard let template = catalog.templates.first(where: { $0.id == templateId }) else {
            print("[AmbientMailGenerator] unknown template id: \(templateId)")
            return false
        }
        mailSite.deliver(makeDraft(for: template))
        return true
    }

    /// Весовой случайный выбор шаблона. Пустой каталог → nil.
    private func weightedRandomTemplate() -> AmbientTemplate? {
        let templates = catalog.templates
        guard !templates.isEmpty else {
            print("[AmbientMailGenerator] empty catalog, nothing to deliver")
            return nil
        }
        let total = templates.reduce(0) { $0 + Swift.max(0, $1.weight) }
        guard total > 0 else {
            return templates.randomElement()
        }
        var needle = Int.random(in: 0..<total)
        for template in templates {
            needle -= Swift.max(0, template.weight)
            if needle < 0 {
                return template
            }
        }
        return templates.last
    }

    private func makeDraft(for template: AmbientTemplate) -> MailDraft {
        MailDraft(
            from: MailPlaceholders.fill("Спам <spam@{{random.domain}}>"),
            subject: MailPlaceholders.fill(template.subject),
            bodyHTML: MailPlaceholders.fill(template.bodyHTML),
            tag: nil,
            timestamp: Date(),
            folder: .inbox
        )
    }

    private func randomInterval() -> TimeInterval {
        Double.random(in: deliveryRange)
    }
}