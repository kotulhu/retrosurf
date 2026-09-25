import Foundation

/// Состояние love.su. Анкеты целиком приходят из profiles.json и никогда не
/// хранятся в state; архив переписок — внутренний мессенджер сайта (нетематично
/// pochta.su, задержки ответов 3–10 с хранятся в `pendingChatReplies`).
///
/// `threads` индексируются profileID анкеты. `pendingChatReplies` — ответы NPC,
/// запланированные на будущую дату; они «приходят» при следующем показе страницы
/// или на 1-секундном тике, а не в момент отправки письма.
struct LoveState: Codable, Sendable {
    struct ChatMessage: Codable, Sendable, Identifiable {
        enum Sender: String, Codable, Sendable {
            case player
            case npc
        }

        let id: Int
        let sender: Sender
        let textHTML: String
        let timestamp: Date
        let attachmentName: String?
        var isRead: Bool
    }

    struct PendingChatReply: Codable, Sendable {
        let profileID: String
        let textHTML: String
        let attachmentName: String?
        let deliverAt: Date
        let tag: String?
    }

    /// Внутренний chat-тред с одним профилем.
    struct ChatThread: Codable, Sendable {
        var messages: [ChatMessage] = []
    }

    /// Черновик сообщения во внутреннем мессенджере для тредов с вложениями.
    struct ChatDraft: Codable, Sendable {
        var text: String = ""
        var attachmentName: String? = nil
    }

    var visitedProfileIDs: Set<String> = []
    var threads: [String: ChatThread] = [:]
    var pendingChatReplies: [PendingChatReply] = []
    var drafts: [String: ChatDraft] = [:]
    var nextMessageID: Int = 1
}