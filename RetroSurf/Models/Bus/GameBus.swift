import Foundation

/// The single typed event bus for domain events. Everything that changes the
/// world state announces itself here; systems (quests, progress, debug) listen
/// by subscribing. No Combine, no NotificationCenter dictionaries — only typed
/// payloads.
@MainActor
final class GameBus: ObservableObject {
    enum Event: Sendable {
        case fileDownloaded(FileDownloadedEvent)
        case fileAttached(FileAttachedEvent)
        case fileSent(FileSentEvent)
        case fileReceived(FileReceivedEvent)
        case fileRemoved(FileRemovedEvent)
        case mailSent(MailSentEvent)
        case mailReceived(MailReceivedEvent)
        case flagChanged(FlagChangedEvent)
        /// Emitted when a quest reward grants a named artifact.
        case artifactEarned(ArtifactEarnedEvent)
        /// Emitted when the browser sends bytes up the line (mail uploads,
        /// forum posts). Drives the session stats.
        case bytesTransferred(BytesTransferredEvent)
        /// Emitted when a file download completes. Drives the session stats.
        case bytesDownloaded(BytesDownloadedEvent)
        /// Emitted when the player writes a message inside love.su's internal
        /// messenger. Absolutely NOT a pochta mail event — NPC chat replies
        /// listen to this, never to `.mailSent`.
        case loveMessageSent(LoveMessageSentEvent)
        /// Emitted when scheduled NPC chat replies become visible in the thread.
        case loveMessageDelivered([String])
    }

    private var subscribers: [UUID: (Event) -> Void] = [:]

    init() {}

    @discardableResult
    func subscribe(_ handler: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    func publish(_ event: Event) {
        #if DEBUG
        trace(event)
        #endif
        // Synchronous, in order of subscription. A handler that throws never
        // happens — the signature is non-throwing by design.
        for handler in subscribers.values {
            handler(event)
        }
    }

    private func trace(_ event: Event) {
        switch event {
        case .fileDownloaded(let e):
            print("[GameBus] fileDownloaded \(e.contentId) → \(e.instanceId) (\(e.name))")
        case .fileAttached(let e):
            print("[GameBus] fileAttached \(e.contentId) → \(e.instanceId) [draft \(e.draftId)]")
        case .fileSent(let e):
            print("[GameBus] fileSent \(e.contentId) → \(e.instanceId) в письме \(e.messageId) для \(e.to)")
        case .fileReceived(let e):
            print("[GameBus] fileReceived \(e.contentId) → \(e.instanceId) письмо \(e.messageId) от \(e.from)")
        case .fileRemoved(let e):
            print("[GameBus] fileRemoved \(e.contentId) → \(e.instanceId) в \(e.ownerNode)")
        case .mailSent(let e):
            print("[GameBus] mailSent #\(e.messageId) для \(e.to) «\(e.subject)» вложения: \(e.attachmentContentIds)")
        case .mailReceived(let e):
            print("[GameBus] mailReceived #\(e.messageId) от \(e.from) «\(e.subject)»")
        case .flagChanged(let e):
            print("[GameBus] flagChanged \(e.key) = \(e.value)")
        case .artifactEarned(let e):
            print("[GameBus] artifactEarned \(e.artifactId)")
        case .bytesTransferred(let e):
            print("[GameBus] bytesTransferred \(e.bytes) [\(e.source)]")
        case .bytesDownloaded(let e):
            print("[GameBus] bytesDownloaded \(e.bytes) (\(e.contentId))")
        case .loveMessageSent(let e):
            print("[GameBus] loveMessageSent → \(e.profileID) «\(e.body.prefix(40))» вложения: \(e.attachmentContentIds)")
        case .loveMessageDelivered(let tags):
            print("[GameBus] loveMessageDelivered tg: \(tags.joined(separator: ","))")
        }
    }
}

// MARK: - Event payloads (all Sendable)

struct FileDownloadedEvent: Sendable {
    let contentId: String
    let instanceId: String
    let name: String
    let sizeBytes: Int
    let hasVirus: Bool
    let downloadedAt: Date
}

struct FileAttachedEvent: Sendable {
    let contentId: String
    let instanceId: String
    let draftId: String
}

struct FileSentEvent: Sendable {
    let contentId: String
    let instanceId: String
    let messageId: Int
    let to: String
}

struct FileReceivedEvent: Sendable {
    let contentId: String
    let instanceId: String
    let messageId: Int
    let from: String
}

struct FileRemovedEvent: Sendable {
    let contentId: String
    let instanceId: String
    let ownerNode: String
}

struct MailSentEvent: Sendable {
    let messageId: Int
    let to: String
    let subject: String
    let attachmentContentIds: [String]
    let tag: String?
    let sentAt: Date
}

struct MailReceivedEvent: Sendable {
    let messageId: Int
    let from: String
    let subject: String
    let tag: String?
    let receivedAt: Date
}

struct FlagChangedEvent: Sendable {
    let key: String
    let value: Bool
}

/// A quest reward that grants one of the named artifacts.
struct ArtifactEarnedEvent: Sendable {
    let artifactId: String
}

/// Bytes sent up the line (uploads, posts) — drives session stats.
struct BytesTransferredEvent: Sendable {
    let bytes: Int
    /// Where the traffic happened: "mail" | "forum" | "file".
    let source: String
    let occurredAt: Date
}

/// Bytes received from completed downloads — drives session stats.
struct BytesDownloadedEvent: Sendable {
    let bytes: Int
    let contentId: String
    let occurredAt: Date
}

struct LoveMessageSentEvent: Sendable {
    let messageId: Int
    let profileID: String
    let body: String
    let attachmentContentIds: [String]
    let sentAt: Date
}