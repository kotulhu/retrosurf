import Foundation

struct SenderCatalog: Codable, Sendable {
    let archetypes: [SenderArchetype]

    /// Decodes `senders.json` from the app bundle. A missing or malformed
    /// resource logs and yields an empty catalog (the game still runs).
    static func loadFromBundle(named name: String = "senders", in bundle: Bundle = .main) -> SenderCatalog {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(SenderCatalog.self, from: data) else {
            print("[SenderCatalog] failed to load \(name).json from \(bundle.bundlePath)")
            return SenderCatalog(archetypes: [])
        }
        return catalog
    }

    func archetype(withId id: String) -> SenderArchetype? {
        archetypes.first { $0.id == id }
    }

    /// Archetypes that may appear on the given site, in catalog order.
    func archetypes(forSite siteId: String) -> [SenderArchetype] {
        archetypes.filter { $0.allowedSites.contains(siteId) }
    }
}