import Foundation

/// Весь контент фан-клуба «Полнолуние» — био участников, дискография,
/// тексты, MP3-каталог и стартовые записи гостевой. Живёт целиком в
/// content.json: ни одна строка на сайте не захардкожена в Swift.
struct FanClubContent: Codable, Sendable {
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

    struct Member: Codable, Sendable {
        let id: String
        let name: String
        let role: String
        let bio: String
    }

    struct Album: Codable, Sendable {
        let year: String
        let title: String
        let description: String
    }

    struct Song: Codable, Sendable {
        let id: String
        let title: String
        let lyrics: String
    }

    struct Mp3: Codable, Sendable {
        let id: String
        let title: String
        let description: String
        let sizeBytes: Int
        let hasVirus: Bool
        let fileName: String
    }

    struct SeedEntry: Codable, Sendable {
        let id: String
        let author: String
        let email: String
        let text: String
        let daysAgo: Int
    }

    let site: SiteMeta
    let about: [String]
    let members: [Member]
    let discography: [Album]
    let songs: [Song]
    let mp3: [Mp3]
    let seedGuestbook: [SeedEntry]

    static var emptyFallback: FanClubContent {
        FanClubContent(
            site: .emptyFallback,
            about: [],
            members: [],
            discography: [],
            songs: [],
            mp3: [],
            seedGuestbook: []
        )
    }

    static func loadFromBundle() -> FanClubContent {
        for candidate in [
            Bundle.main.url(
                forResource: "content", withExtension: "json",
                subdirectory: "Sites/polnolunie-fanclub.su"
            ),
            Bundle.main.url(
                forResource: "content", withExtension: "json",
                subdirectory: "Sites"
            ),
            Bundle.main.resourceURL?
                .appendingPathComponent("Sites/polnolunie-fanclub.su/content.json"),
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
    static func load(contentAt url: URL) -> FanClubContent {
        guard let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(FanClubContent.self, from: data) else {
            return .emptyFallback
        }
        return content
    }

    func mp3(id: String) -> Mp3? {
        mp3.first { $0.id == id }
    }

    func song(id: String) -> Song? {
        songs.first { $0.id == id }
    }
}
