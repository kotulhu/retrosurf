import Foundation

/// Контент love.su — метаданные сайта и анкеты пользователей. Живёт
/// целиком в profiles.json: ни одна строка на сайте не захардкожена в Swift.
struct LoveContent: Codable, Sendable {
    struct SiteMeta: Codable, Sendable {
        let title: String
        let tagline: String
        let warning: String
        let footer: String
        let navLabel: String

        static let emptyFallback = SiteMeta(
            title: "",
            tagline: "",
            warning: "",
            footer: "",
            navLabel: ""
        )
    }

    struct Profile: Codable, Sendable, Identifiable {
        let id: String
        let nickname: String
        let email: String
        let age: Int
        let city: String
        let about: String
        let interests: [String]
        let lookingFor: String
        let photoPlaceholder: String
    }

    let site: SiteMeta
    let profiles: [Profile]

    static var emptyFallback: LoveContent {
        LoveContent(site: .emptyFallback, profiles: [])
    }

    static func loadFromBundle() -> LoveContent {
        for candidate in [
            Bundle.main.url(
                forResource: "profiles", withExtension: "json",
                subdirectory: "sites/love.su"
            ),
            Bundle.main.url(
                forResource: "profiles", withExtension: "json",
                subdirectory: "Sites/love.su"
            ),
            Bundle.main.resourceURL?
                .appendingPathComponent("sites/love.su/profiles.json"),
        ] {
            guard let candidate else { continue }
            let content = load(contentAt: candidate)
            if !content.site.title.isEmpty {
                return content
            }
        }
        return .emptyFallback
    }

    /// Отсутствующий или битый JSON никогда не роняет приложение:
    /// возвращается пустой фолбэк, сайт отдаёт каркас без контента.
    static func load(contentAt url: URL) -> LoveContent {
        guard let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(LoveContent.self, from: data) else {
            return .emptyFallback
        }
        return content
    }

    func profile(id: String) -> Profile? {
        profiles.first { $0.id == id }
    }

    func profile(withEmail email: String) -> Profile? {
        let needle = email.trimmingCharacters(in: .whitespaces).lowercased()
        return profiles.first { $0.email.trimmingCharacters(in: .whitespaces).lowercased() == needle }
    }
}