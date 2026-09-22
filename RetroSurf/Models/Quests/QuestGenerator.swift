import Combine
import Foundation

enum MessageChannel: String, Codable, Sendable {
    case mail
    case chat
}

enum ChannelTiming {
    static func defaultDelayRange(for channel: MessageChannel) -> ClosedRange<TimeInterval> {
        switch channel {
        case .mail: 180...900
        case .chat: 5...30
        }
    }
}

struct PendingDelivery: Codable, Identifiable, Sendable {
    let id: String
    let channel: MessageChannel
    let deliverAt: Date
    let targetSiteId: String
    let message: QuestMessage
}

/// Persists planned delivery timestamps rather than a running timer, so a
/// message remains scheduled while the app is closed and is handled next tick.
@MainActor
final class MessageScheduler: ObservableObject {
    private enum Keys {
        static let pendingDeliveries = "MessageScheduler.pendingDeliveries"
    }

    private let defaults: UserDefaults
    @Published private(set) var pendingDeliveries: [PendingDelivery]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.pendingDeliveries),
           let deliveries = try? JSONDecoder().decode([PendingDelivery].self, from: data) {
            pendingDeliveries = deliveries
        } else {
            pendingDeliveries = []
        }
    }

    func schedule(
        channel: MessageChannel,
        targetSiteId: String,
        message: QuestMessage,
        overrideDelayRange: ClosedRange<TimeInterval>? = nil
    ) {
        let range = overrideDelayRange ?? ChannelTiming.defaultDelayRange(for: channel)
        let delivery = PendingDelivery(
            id: UUID().uuidString,
            channel: channel,
            deliverAt: Date().addingTimeInterval(TimeInterval.random(in: range)),
            targetSiteId: targetSiteId,
            message: message
        )
        pendingDeliveries.append(delivery)
        persist()
#if DEBUG
        let category = delivery.channel == .mail ? "Mail" : "Chat"
        let seconds = Int(delivery.deliverAt.timeIntervalSinceNow)
        DebugLogger.shared.log(category, "scheduled '\(delivery.id)' → '\(delivery.targetSiteId)' (delay \(seconds) s)")
#endif
    }

    func processDueDeliveries(deliverHandler: (PendingDelivery) -> Void) {
        let due = pendingDeliveries.filter { $0.deliverAt <= Date() }
        for delivery in due {
            deliverHandler(delivery)
#if DEBUG
            let category = delivery.channel == .mail ? "Mail" : "Chat"
            DebugLogger.shared.log(category, "delivered '\(delivery.id)' → '\(delivery.targetSiteId)'")
#endif
        }
        guard !due.isEmpty else { return }
        let deliveredIDs = Set(due.map(\.id))
        pendingDeliveries.removeAll { deliveredIDs.contains($0.id) }
        persist()
    }

    /// Removes all scheduled deliveries (used by the debug progress reset).
    func clearAll() {
        pendingDeliveries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pendingDeliveries) else { return }
        defaults.set(data, forKey: Keys.pendingDeliveries)
        defaults.synchronize()
    }
}

/// Converts QuestDefinitions into concrete letters and pushes them into
/// registered interactive sites (pochta.su). Senders are resolved once per
/// archetypeId, so all quests from "friend" come from the same person.
@MainActor
final class QuestGenerator: ObservableObject {
    private let quests: [QuestDefinition]
    private let senders: SenderCatalog
    let messageScheduler: MessageScheduler
    private weak var registry: SiteRegistry?

    /// archetypeId -> concrete Sender. Cached per archetype, not per quest.
    private var senderCache: [String: Sender] = [:]

    init(
        quests: [QuestDefinition],
        senders: SenderCatalog,
        registry: SiteRegistry,
        messageScheduler: MessageScheduler
    ) {
        self.quests = quests
        self.senders = senders
        self.registry = registry
        self.messageScheduler = messageScheduler
    }

    /// Loads quests.json from the app bundle. Logs and yields [] on failure.
    static func loadQuestsFromBundle(named name: String = "quests", in bundle: Bundle = .main) -> [QuestDefinition] {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let quests = try? JSONDecoder().decode([QuestDefinition].self, from: data) else {
            print("[QuestGenerator] failed to load \(name).json from \(bundle.bundlePath)")
            return []
        }
        return quests
    }

    func quest(id: String) -> QuestDefinition? {
        quests.first { $0.id == id }
    }

    // MARK: - Issue paths

    /// Deliver a quest to its first preferredSite where the sender archetype
    /// is allowed AND the site is registered. Returns false (quest stays
    /// pending) when no such site exists — including when resolveSender fails.
    @discardableResult
    func deliver(_ quest: QuestDefinition) -> Bool {
        for siteID in quest.delivery.preferredSites {
            guard let target = registry?.site(withID: siteID) as? QuestLetterReceiver else { continue }
            guard let sender = resolveSender(for: quest, targetSiteId: siteID) else { continue }
            let message = makeMessage(for: quest, sender: sender)
            _ = target.deliver(message)
            print("[QuestGenerator] delivered '\(quest.id)' to '\(siteID)' from \(sender.address)")
            return true
        }
        print("[QuestGenerator] '\(quest.id)' stays pending (no allowed, registered target)")
        return false
    }

    /// Deliver a quest directly at a specific site, using the same sender
    /// resolution and templating as a normal issue. Returns false if the
    /// archetype isn't allowed there or the target isn't a letter receiver.
    @discardableResult
    func forceIssue(_ questID: String, into siteID: String) -> Bool {
        guard let quest = quest(id: questID) else {
            print("[QuestGenerator] forceIssue: unknown quest '\(questID)'")
            return false
        }
        guard let target = registry?.site(withID: siteID) as? QuestLetterReceiver else {
            print("[QuestGenerator] forceIssue: '\(siteID)' is not a quest letter receiver")
            return false
        }
        guard let sender = resolveSender(for: quest, targetSiteId: siteID) else { return false }
        let message = makeMessage(for: quest, sender: sender)
        _ = target.deliver(message)
        print("[QuestGenerator] forceIssued '\(quest.id)' at '\(siteID)' from \(sender.address)")
        return true
    }

    func clearSenderCache() {
        senderCache.removeAll()
    }

    /// Runs from the application's shared heartbeat. Due messages are removed
    /// only after their persisted timestamps have been reached.
    func processDueDeliveries() {
        messageScheduler.processDueDeliveries { [weak self] delivery in
            guard let target = self?.registry?.site(withID: delivery.targetSiteId) as? MessageCapable else {
                print("[QuestGenerator] scheduled delivery '\(delivery.id)' has no target '\(delivery.targetSiteId)'")
                return
            }
            _ = target.deliver(delivery.message)
            print("[QuestGenerator] delivered scheduled '\(delivery.id)' to '\(delivery.targetSiteId)'")
        }
    }

    // MARK: - Sender resolution

    /// Resolve (and cache) the concrete Sender for an archetypeId.
    /// Nil when the archetype is missing, not allowed on `targetSiteId`,
    /// or has an empty name pool.
    private func resolveSender(for quest: QuestDefinition, targetSiteId: String) -> Sender? {
        guard let archetype = senders.archetype(withId: quest.delivery.senderArchetypeId) else {
            print("[QuestGenerator] '\(quest.id)': unknown archetype '\(quest.delivery.senderArchetypeId)'")
            return nil
        }
        guard archetype.allowedSites.contains(targetSiteId) else {
            print("[QuestGenerator] '\(quest.id)': archetype '\(archetype.id)' not allowed on '\(targetSiteId)'")
            return nil
        }
        if let cached = senderCache[archetype.id] {
            return cached
        }
        guard let name = archetype.namePool.randomElement() else {
            print("[QuestGenerator] '\(quest.id)': archetype '\(archetype.id)' has an empty name pool")
            return nil
        }
        let address: String
        if let override = quest.delivery.senderAddressOverride {
            address = override
        } else if let domain = archetype.domainPool.randomElement() {
            address = "\(name.login)@\(domain)"
        } else {
            address = "\(name.login)@\(archetype.id).su"
        }
        let sender = Sender(
            archetypeId: archetype.id,
            name: name,
            address: address,
            kind: archetype.kind,
            gender: archetype.gender
        )
        senderCache[archetype.id] = sender
        return sender
    }

    // MARK: - Templating

    private func makeMessage(for quest: QuestDefinition, sender: Sender) -> QuestMessage {
        QuestMessage(
            questID: quest.id,
            sender: sender,
            subject: applyTemplates(quest.delivery.subject, sender: sender, quest: quest),
            bodyHTML: applyTemplates(quest.delivery.bodyHTML, sender: sender, quest: quest),
            tag: quest.delivery.tag,
            messageCategory: quest.delivery.messageCategory,
            relatedSiteId: quest.delivery.relatedSiteId,
            timestamp: Date()
        )
    }

    /// {{sender.name}} -> full name, {{sender.firstName}} -> first name,
    /// {{sender.address}} -> address, {{quest.title}} -> title.
    /// Unmatched placeholders are left as-is (visible during debug).
    private func applyTemplates(_ text: String, sender: Sender, quest: QuestDefinition) -> String {
        var out = text
        let replacements = [
            "{{sender.name}}": sender.name.full,
            "{{sender.firstName}}": sender.name.firstName,
            "{{sender.address}}": sender.address,
            "{{quest.title}}": quest.title
        ]
        for (token, value) in replacements {
            out = out.replacingOccurrences(of: token, with: value)
        }
        return out
    }
}
