import Foundation

/// One concrete copy of a `FileContent` living in a named node of the file
/// graph. Nodes are opaque ownerNode strings: "downloads", "mail:draft:42",
/// "mail:sent:17", "npc:serega:inbox:08". Deleting one instance never touches
/// other copies of the same content.
struct FileInstance: Sendable, Identifiable, Hashable, Codable {
    let instanceId: String
    let content: FileContent
    let createdAt: Date
    /// "downloads", "mail:draft:42", "mail:sent:17", "npc:serega:inbox:08".
    let ownerNode: String

    var id: String { instanceId }
}