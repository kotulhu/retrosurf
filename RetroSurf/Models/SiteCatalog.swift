import Foundation
import SwiftUI

enum ModemTier: Int, CaseIterable, Comparable {
    case v14_4 = 0
    case v28_8 = 1
    case v56 = 2
    case isdn = 3

    static func < (lhs: ModemTier, rhs: ModemTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var fullLabel: String {
        switch self {
        case .v14_4: "14.4 kbps"
        case .v28_8: "28.8 kbps"
        case .v56: "56 kbps"
        case .isdn: "ISDN 64 kbps"
        }
    }
}

extension ModemTier: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(Int.self), let tier = ModemTier(rawValue: raw) {
            self = tier
            return
        }
        if let asString = try? container.decode(String.self) {
            if let fromInt = Int(asString), let tier = ModemTier(rawValue: fromInt) {
                self = tier
                return
            }
            if let tier = ModemTier.allCases.first(where: { "\($0)" == asString }) {
                self = tier
                return
            }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ModemTier value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum SiteCategory: String, Codable, CaseIterable {
    case personalPage = "personal_page"
    case music = "music"
    case news = "news"
    case forum = "forum"
    case chat = "chat"
    case portal = "portal"
    case games = "games"
    case other = "other"

    var title: String {
        switch self {
        case .personalPage: "Личные страницы"
        case .music: "Музыка"
        case .news: "Новости"
        case .forum: "Форумы"
        case .chat: "Чаты"
        case .portal: "Порталы и каталоги"
        case .games: "Игры"
        case .other: "Разное"
        }
    }

    var icon: String {
        switch self {
        case .personalPage: "ДС"
        case .music: "♪"
        case .news: "Н"
        case .forum: "Ф"
        case .chat: "Ч"
        case .portal: "К"
        case .games: "И"
        case .other: "…"
        }
    }
}

struct SiteMeta: Codable {
    let displayDomain: String
    let title: String
    let shortDescription: String?
    let category: SiteCategory?
    let keywords: [String]?
    let requiredTier: ModemTier?
    let interactiveExperienceID: String?
    let requiredQuestID: String?
}

enum SiteSource: Codable, Equatable {
    case archived(url: String, eraYear: Int)
    case fictional(resourceName: String)
    case curatedArchive(resourceName: String)
    case interactive(experienceID: String)
}

struct SiteEntry: Codable, Identifiable {
    let id: String
    let displayDomain: String
    let title: String
    let shortDescription: String
    let keywords: [String]
    let category: SiteCategory
    let source: SiteSource
    let requiredTier: ModemTier
    let requiredQuestID: String?
    let isUserAdded: Bool
}

@MainActor
enum SiteAccess {
    static func status(
        for entry: SiteEntry,
        progress: GameProgress,
        quests: QuestManager
    ) -> (locked: Bool, reason: String?) {
        if let requiredQuestID = entry.requiredQuestID,
           !quests.isCompleted(requiredQuestID) {
            let reason: String
            if requiredQuestID == QuestManager.registrationQuestID {
                reason = "Требуется зарегистрированная почта"
            } else {
                reason = quests.quest(id: requiredQuestID)
                    .map { "Требуется выполнить квест: \($0.title)" }
                    ?? "Требуется выполнить квест"
            }
            return (true, reason)
        }
        if entry.requiredTier.rawValue > progress.currentTier.rawValue {
            return (true, "Доступно на скорости \(entry.requiredTier.fullLabel)")
        }
        return (false, nil)
    }
}

@MainActor
final class SiteCatalog: ObservableObject {
    @Published var entries: [SiteEntry] = []

    private var bundledSitesURL: URL {
        Bundle.main.url(forResource: "sites", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent("sites")
            ?? URL(fileURLWithPath: "/nonexistent")
    }

    static var curatedSitesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroSurf", isDirectory: true)
            .appendingPathComponent("CuratedSites", isDirectory: true)
    }

    init() {
        loadAll()
    }

    func loadAll() {
        var result: [SiteEntry] = []
        result += scanDirectory(bundledSitesURL, isUserAdded: false)
        result += scanDirectory(Self.curatedSitesURL, isUserAdded: true)
        entries = result
    }

    func entry(forDomain domain: String) -> SiteEntry? {
        let needle = Self.normalizedDomain(domain)
        guard !needle.isEmpty else { return nil }
        return entries.first { candidate in
            let d = Self.normalizedDomain(candidate.displayDomain)
            if d == needle { return true }
            if d.hasPrefix(needle + "/") { return true }
            if needle.hasPrefix(d + "/") { return true }
            return false
        }
    }

    func entry(id: String) -> SiteEntry? {
        entries.first { $0.id == id }
    }

    func entries(in category: SiteCategory) -> [SiteEntry] {
        entries.filter { $0.category == category }
    }

    static func normalizedDomain(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func defaultTitle(from slug: String) -> String {
        let cleaned = slug
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.first else { return slug }
        return String(first).uppercased() + cleaned.dropFirst()
    }

    func page(for entry: SiteEntry) -> (html: String, baseURL: URL?)? {
        guard case .curatedArchive = entry.source else { return nil }
        let directory = directoryURL(for: entry)
        let pageURL = directory.appendingPathComponent("page.html")
        guard FileManager.default.fileExists(atPath: pageURL.path),
              let data = try? Data(contentsOf: pageURL),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        let baseString = directory.absoluteString.hasSuffix("/")
            ? directory.absoluteString
            : directory.absoluteString + "/"
        return (html, URL(string: baseString))
    }

    func updateCuratedEntry(id: String, newTitle: String) throws {
        let cleaned = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let entry = entry(id: id), entry.isUserAdded else { return }
        let directory = directoryURL(for: entry)
        let current = readMeta(at: directory)
        let meta = SiteMeta(
            displayDomain: current?.displayDomain ?? entry.displayDomain,
            title: cleaned,
            shortDescription: current?.shortDescription,
            category: current?.category,
            keywords: current?.keywords,
            requiredTier: current?.requiredTier,
            interactiveExperienceID: current?.interactiveExperienceID,
            requiredQuestID: current?.requiredQuestID
        )
        try writeMeta(meta, at: directory)
        loadAll()
    }

    func removeCuratedEntry(id: String) throws {
        guard let entry = entry(id: id), entry.isUserAdded else { return }
        let directory = directoryURL(for: entry)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        loadAll()
    }

    /// Removes every game-created site directory (published static pages and
    /// player-curated content) plus stored homepage photos. Bundled
    /// Resources/sites are never touched. Reloads the catalog afterwards.
    func resetUserCreatedContent() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.curatedSitesURL.path) {
            try? fileManager.removeItem(at: Self.curatedSitesURL)
        }
        let photos = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RetroSurf", isDirectory: true)
            .appendingPathComponent("HomepagePhotos", isDirectory: true)
        if fileManager.fileExists(atPath: photos.path) {
            try? fileManager.removeItem(at: photos)
        }
        loadAll()
    }

    private func scanDirectory(_ url: URL, isUserAdded: Bool) -> [SiteEntry] {
        let fileManager = FileManager.default
        guard let slugs = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return []
        }
        var result: [SiteEntry] = []
        for slug in slugs.sorted() {
            let slugURL = url.appendingPathComponent(slug)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: slugURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            let meta = readMeta(at: slugURL)
            let source: SiteSource
            if let experienceID = meta?.interactiveExperienceID, !experienceID.isEmpty {
                source = .interactive(experienceID: experienceID)
            } else {
                source = .curatedArchive(resourceName: slug)
            }
            result.append(
                SiteEntry(
                    id: slug,
                    displayDomain: meta?.displayDomain ?? slug,
                    title: meta?.title ?? Self.defaultTitle(from: slug),
                    shortDescription: meta?.shortDescription ?? "",
                    keywords: meta?.keywords ?? [],
                    category: meta?.category ?? .other,
                    source: source,
                    requiredTier: meta?.requiredTier ?? .v14_4,
                    requiredQuestID: meta?.requiredQuestID,
                    isUserAdded: isUserAdded
                )
            )
        }
        return result
    }

    private func directoryURL(for entry: SiteEntry) -> URL {
        guard case .curatedArchive(let slug) = entry.source else {
            return URL(fileURLWithPath: "/")
        }
        if entry.isUserAdded {
            return Self.curatedSitesURL.appendingPathComponent(slug)
        }
        return bundledSitesURL.appendingPathComponent(slug)
    }

    private func readMeta(at directory: URL) -> SiteMeta? {
        let metaURL = directory.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(SiteMeta.self, from: data)
    }

    private func writeMeta(_ meta: SiteMeta, at directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meta)
        try data.write(to: directory.appendingPathComponent("meta.json"), options: .atomic)
    }
}