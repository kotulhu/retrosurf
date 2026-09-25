import Foundation

/// Who may write to the player: a real person, an automated robot, or the
/// service itself. Affects nothing yet beyond labeling.
enum SenderKind: String, Codable, Sendable {
    case human
    case robot
    case service
}

enum SenderGender: String, Codable, Sendable {
    case male
    case female
    case none
}

/// A concrete display name plus the login used to build an address.
struct SenderName: Codable, Sendable, Hashable {
    let full: String        // "Сергей Петров"
    let firstName: String   // "Сергей"
    let login: String       // "spetrov" — used to build the address
}

/// A persona family: one archetype = one consistent sender across all quests.
/// Resolved to a concrete `Sender` once and cached per archetypeId.
struct SenderArchetype: Codable, Sendable, Identifiable {
    let id: String                    // "curator", "friend", "family", "love_interest", "robot", "service"
    let displayName: String           // human-readable, used in debug
    let kind: SenderKind
    let gender: SenderGender
    let namePool: [SenderName]        // concrete names to pick from
    let domainPool: [String]          // e.g. ["pochta.su", "mail.su", "chat.su"]
    let allowedSites: [String]        // descriptor.id values where this archetype may appear
}

/// The concrete, fully-resolved sender injected into a delivered message.
struct Sender: Codable, Sendable, Hashable {
    let archetypeId: String
    let name: SenderName
    let address: String
    let kind: SenderKind
    let gender: SenderGender
}