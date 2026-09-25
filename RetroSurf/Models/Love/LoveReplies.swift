import Foundation

/// Одно письмо-ответ от профиля love.su.
struct LoveReply: Codable, Sendable {
    let subject: String
    let bodyHTML: String
}

/// Письма трекера квеста love.su, хранящиеся в Resources/Love/love_replies.json.
/// Каждая запись — готовое сообщение от профиля-симпатии игроку.
struct LoveRepliesCatalog: Codable, Sendable {
    /// Первое приветствие симпатии — открывает переписку сама.
    let opening: LoveReply
    let firstReply: LoveReply
    let secondReply: LoveReply
    let attachmentRequest: LoveReply
    let thanksForAttachment: LoveReply
    /// Короткие случайные реплики для остальных профилей (внутренний чат).
    let pool: [LoveReply]

    static func loadFromBundle(named name: String = "love_replies") -> LoveRepliesCatalog? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[LoveRepliesCatalog] failed to load \(name).json from bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(LoveRepliesCatalog.self, from: data)
        } catch {
            print("[LoveRepliesCatalog] decode error for \(name).json: \(error)")
            return nil
        }
    }
}