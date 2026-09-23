import Combine
import Foundation

/// Рассылка личных писем от NPC игроку:
/// — «молчание»: если игрок не писал персонажу дольше silenceDelayMinutes,
///   NPC шлёт «скучаю»-письмо;
/// — «ответ»: после письма игрока NPC отвечает через 5...15 минут;
/// — лимит: до 3 писем в час на NPC, затем 1 час тишины.
/// Одно письмо за тик; ответ приоритетнее «молчания».
@MainActor
final class NpcMessenger: ObservableObject {
    private let catalog: NpcCatalog
    private let mailSite: MailSite
    private let tickInterval: TimeInterval

    private var task: Task<Void, Never>?

    /// Когда игрок последний раз писал NPC (по id NPC).
    private var lastContactFromPlayer: [String: Date] = [:]
    /// Когда NPC последний раз писал игроку (по id NPC).
    private var lastLetterFromNpc: [String: Date] = [:]
    /// Сколько писем NPC отправил за текущий час.
    private var lettersSentThisHour: [String: Int] = [:]
    /// Начало текущего часа счёта писем.
    private var lettersHourStart: [String: Date] = [:]
    /// Когда NPC снова может писать после срабатывания лимита.
    private var quietUntil: [String: Date] = [:]
    /// Сканированные отправленные письма игрока.
    private var processedSentMessageIds: Set<Int> = []
    /// Когда подойдёт ответ на письмо игрока.
    private var replyDueAt: [String: Date] = [:]
    /// Подавляет мгновенное «молчание» на первом тике.
    private var silenceClockInitialized = false
    /// Следующий шаг диалога для каждого NPC (по id NPC).
    private var conversationStage: [String: Int] = [:]

    init(catalog: NpcCatalog, mailSite: MailSite, tickInterval: TimeInterval = 60) {
        self.catalog = catalog
        self.mailSite = mailSite
        self.tickInterval = tickInterval
    }

    /// Запускает цикл: каждые `tickInterval` секунд — оценка `tickOnce`.
    /// Идемпотентен, уважает отмену.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(tickInterval))
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

    /// Мгновенно шлёт «скучаю»-письмо конкретного NPC.
    @discardableResult
    func forceSilence(from npcId: String) -> Bool {
        guard let npc = catalog.npc(withId: npcId) else {
            print("[NpcMessenger] unknown npc id: \(npcId)")
            return false
        }
        let now = Date()
        guard !rateLimitBlocked(npc, now: now) else { return false }
        guard let template = npc.silenceTemplates.randomElement() else {
            print("[NpcMessenger] no silence template for \(npcId)")
            return false
        }
        deliver(template, from: npc, now: now)
        lastLetterFromNpc[npc.id] = now
        lettersSentThisHour[npc.id, default: 0] += 1
        lastContactFromPlayer[npc.id] = now
        lettersHourStart[npc.id] = lettersHourStart[npc.id] ?? now
        return true
    }

    /// Мгновенно шлёт ответного письма конкретного NPC.
    @discardableResult
    func forceReply(from npcId: String) -> Bool {
        guard let npc = catalog.npc(withId: npcId) else {
            print("[NpcMessenger] unknown npc id: \(npcId)")
            return false
        }
        let now = Date()
        guard !rateLimitBlocked(npc, now: now) else { return false }
        guard let template = npc.replyTemplates.randomElement() else {
            print("[NpcMessenger] no reply template for \(npcId)")
            return false
        }
        deliver(template, from: npc, now: now)
        lastLetterFromNpc[npc.id] = now
        lettersSentThisHour[npc.id, default: 0] += 1
        replyDueAt.removeValue(forKey: npc.id)
        lettersHourStart[npc.id] = lettersHourStart[npc.id] ?? now
        return true
    }

    /// Один проход оценки таймера. Возвращает id NPC, которому ушло письмо,
    /// или nil, если письма не было.
    @discardableResult
    func tickOnce(now: Date = Date()) -> String? {
        resetHourlyCounters(now: now)

        scanSentMessages(now: now)

        // Первый тик = точка отсчёта «молчания» для тех, кому игрок не писал.
        if !silenceClockInitialized {
            silenceClockInitialized = true
            for npc in catalog.npcs where lastContactFromPlayer[npc.id] == nil {
                lastContactFromPlayer[npc.id] = now
            }
        }

        // Ответ приоритетнее «молчания».
        for npc in catalog.npcs {
            guard let due = replyDueAt[npc.id], due <= now else { continue }
            guard !rateLimitBlocked(npc, now: now) else { continue }
            guard let template = replyTemplate(for: npc) else {
                print("[NpcMessenger] no reply template for \(npc.id)")
                replyDueAt.removeValue(forKey: npc.id)
                continue
            }
            deliver(template, from: npc, now: now)
            lastLetterFromNpc[npc.id] = now
            lettersSentThisHour[npc.id, default: 0] += 1
            replyDueAt.removeValue(forKey: npc.id)
            return npc.id
        }

        for npc in catalog.npcs {
            guard replyDueAt[npc.id] == nil else { continue }
            guard let last = lastContactFromPlayer[npc.id] else { continue }
            let delay = TimeInterval(npc.silenceDelayMinutes * 60)
            guard now.timeIntervalSince(last) >= delay else { continue }
            guard !rateLimitBlocked(npc, now: now) else { continue }
            guard let template = npc.silenceTemplates.randomElement() else {
                print("[NpcMessenger] no silence template for \(npc.id)")
                continue
            }
            deliver(template, from: npc, now: now)
            lastLetterFromNpc[npc.id] = now
            lettersSentThisHour[npc.id, default: 0] += 1
            lastContactFromPlayer[npc.id] = now
            return npc.id
        }

        return nil
    }

    // MARK: - Internals

    /// Выбирает ответ для NPC: следующий шаг диалога, пока он есть, иначе
    /// случайное письмо из replyTemplates. Применяет эффекты шага.
    private func replyTemplate(for npc: NpcProfile) -> NpcTemplate? {
        if let conversation = npc.conversation, !conversation.isEmpty {
            let stage = conversationStage[npc.id] ?? 0
            guard stage < conversation.count else {
                return npc.replyTemplates.randomElement()
            }
            let step = conversation[stage]
            conversationStage[npc.id] = stage + 1
            applyEffects(step.effects)
            return step.reply
        }
        return npc.replyTemplates.randomElement()
    }

    /// Рассылает эффекты шага диалога через NotificationCenter (.retroFlagSet),
    /// чтобы заинтересованные системы (установщик странички) узнали о флаге.
    private func applyEffects(_ effects: [NpcEffect]?) {
        for effect in effects ?? [] {
            guard let flags = effect.setFlag else { continue }
            for (key, value) in flags {
                NotificationCenter.default.post(
                    name: .retroFlagSet,
                    object: nil,
                    userInfo: ["key": key, "value": value]
                )
            }
        }
    }

    /// Находит новые отправленные игроком письма и планирует ответы.
    private func scanSentMessages(now: Date) {
        for message in mailSite.state.messages where message.folder == .sent {
            guard !processedSentMessageIds.contains(message.id) else { continue }
            processedSentMessageIds.insert(message.id)
            guard let npc = catalog.npc(withEmail: message.to) else { continue }
            lastContactFromPlayer[npc.id] = message.timestamp
            if replyDueAt[npc.id] == nil {
                replyDueAt[npc.id] = now.addingTimeInterval(replyDelay())
            }
        }
    }

    /// Сбрасывает почасовые счётчики писем у всех NPC.
    private func resetHourlyCounters(now: Date) {
        for npc in catalog.npcs {
            guard let hourStart = lettersHourStart[npc.id] else {
                lettersHourStart[npc.id] = now
                lettersSentThisHour[npc.id] = 0
                continue
            }
            if now.timeIntervalSince(hourStart) >= 3600 {
                lettersHourStart[npc.id] = now
                lettersSentThisHour[npc.id] = 0
            }
        }
    }

    /// true, если NPC молчит или уже исчерпал лимит (тогда включается пауза в час).
    private func rateLimitBlocked(_ npc: NpcProfile, now: Date) -> Bool {
        if let quiet = quietUntil[npc.id], quiet > now {
            print("[NpcMessenger] \(npc.id) quiet until \(quiet)")
            return true
        }
        if lettersSentThisHour[npc.id, default: 0] >= 3 {
            quietUntil[npc.id] = now.addingTimeInterval(3600)
            print("[NpcMessenger] \(npc.id) sent 3 letters, quiet for 1 hour")
            return true
        }
        return false
    }

    private func deliver(_ template: NpcTemplate, from npc: NpcProfile, now: Date) {
        let extra: [String: String] = [
            "npc.name": npc.displayName,
            "npc.email": npc.email,
            "player.username": mailSite.currentUsername ?? "пользователь"
        ]
        mailSite.deliver(
            MailDraft(
                from: "\(npc.displayName) <\(npc.email)>",
                subject: MailPlaceholders.fill(template.subject, extra: extra),
                bodyHTML: MailPlaceholders.fill(template.bodyHTML, extra: extra),
                tag: nil,
                timestamp: now,
                folder: .inbox
            )
        )
    }

    private func replyDelay() -> TimeInterval {
        Double.random(in: 300...900)
    }
}