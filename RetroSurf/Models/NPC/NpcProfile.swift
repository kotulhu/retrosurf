import Foundation

/// Один персонаж, который пишет игроку личные письма.
struct NpcProfile: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let email: String
    let pageUrl: String
    let gender: String
    let age: Int
    let personality: String
    let silenceDelayMinutes: Int
    let silenceTemplates: [NpcTemplate]
    let replyTemplates: [NpcTemplate]
    /// Пошаговый диалог: каждый ответ по очереди, пока не закончатся шаги,
    /// дальше — случайные письма из replyTemplates.
    let conversation: [NpcConversationStep]?
}

/// Одно письмо-шаблон персонажа (до подстановки плейсхолдеров).
struct NpcTemplate: Codable, Sendable {
    let subject: String
    let bodyHTML: String
}

/// Один шаг диалога NPC: ответ на письмо игрока + эффекты после отправки.
struct NpcConversationStep: Codable, Sendable {
    let reply: NpcTemplate
    let effects: [NpcEffect]?
}

/// Эффекты, применяемые после отправки письма NPC.
struct NpcEffect: Codable, Sendable {
    /// Флаги, которые надо выставить: ключ → значение.
    let setFlag: [String: Bool]?
}

extension Notification.Name {
    static let retroFlagSet = Notification.Name("retroFlagSet")
}

/// Каталог NPC из Resources/NPC/{name}.json. На пустой/битый каталог не падает.
struct NpcCatalog: Codable, Sendable {
    let npcs: [NpcProfile]

    init(npcs: [NpcProfile] = []) {
        self.npcs = npcs
    }

    /// Загружает Resources/NPC/{name}.json (копируется в корень Contents/Resources).
    /// При ошибке загрузки или декодирования возвращает пустой каталог и печатает причину.
    static func loadFromBundle(named name: String = "npcs") -> NpcCatalog {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("[NpcCatalog] not found: Resources/NPC/\(name).json")
            return NpcCatalog()
        }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(NpcCatalog.self, from: data)
            print("[NpcCatalog] loaded \(catalog.npcs.count) NPC(s) from \(url.path)")
            return catalog
        } catch {
            print("[NpcCatalog] decoding error: \(error)")
            return NpcCatalog()
        }
    }

    /// Персонаж по адресу почты (без учёта регистра, с обрезкой пробелов).
    func npc(withEmail email: String) -> NpcProfile? {
        let needle = email.trimmingCharacters(in: .whitespaces).lowercased()
        return npcs.first { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == needle }
    }

    /// Персонаж по id.
    func npc(withId id: String) -> NpcProfile? {
        npcs.first { $0.id == id }
    }
}