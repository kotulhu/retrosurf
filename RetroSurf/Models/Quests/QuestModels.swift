import Foundation

/// Immutable quest description driven by Resources/Quests/quests.json.
struct QuestDefinition: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String
    /// descriptor.id of the site this quest is about (e.g. "mail").
    let targetSiteID: String
    let delivery: QuestDelivery
}

/// How (and where) a quest's letter gets delivered.
struct QuestDelivery: Codable, Sendable {
    /// Descriptor ids the letter may be pushed into, in priority order.
    let preferredSites: [String]
    let senderArchetypeId: String
    /// Optional; if set, overrides the generated address for this delivery.
    let senderAddressOverride: String?
    /// Subject and bodyHTML may contain placeholders {{sender.name}}
    /// {{sender.firstName}} {{sender.address}} {{quest.title}}.
    let subject: String
    /// Plain HTML; run through template substitution before delivery.
    let bodyHTML: String
    /// Opaque tag; read-once emits "mail.read.<tag>".
    let tag: String?
    let messageCategory: String?
    let relatedSiteId: String?
    let metadata: [String: String]
}

/// The fully-resolved letter handed to a QuestLetterReceiver (MailSite).
struct QuestMessage: Codable, Sendable {
    let questID: String
    let sender: Sender
    let subject: String
    let bodyHTML: String
    let tag: String?
    let messageCategory: String?
    let relatedSiteId: String?
    let timestamp: Date
}

/// Any interactive site that can receive a scheduled message. Mail uses this
/// today; chat sites will use the same capability when they are added.
@MainActor
protocol MessageCapable: AnyObject {
    func deliver(_ message: QuestMessage) -> Int
}

/// Compatibility name for existing quest delivery code.
protocol QuestLetterReceiver: MessageCapable {}
