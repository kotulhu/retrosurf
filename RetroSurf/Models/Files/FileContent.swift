import Foundation

/// Immutable description of a downloadable file. One `FileContent` describes
/// a catalog entry (a files.su file id); many `FileInstance`s can reference it.
struct FileContent: Sendable, Hashable, Codable {
    let contentId: String
    let name: String
    let sizeBytes: Int
    let hasVirus: Bool
    /// Reserved for future virus simulation; currently always nil.
    let virusKind: String?
    let sourceURL: URL
    let downloadedAt: Date
}