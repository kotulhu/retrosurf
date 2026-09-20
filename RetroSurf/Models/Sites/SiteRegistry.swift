import Foundation

@MainActor
final class SiteRegistry {
    private var sites: [String: any InteractiveSite] = [:]

    func register(_ site: any InteractiveSite) {
        sites[site.descriptor.id] = site
    }

    func site(forHost host: String) -> (any InteractiveSite)? {
        let needle = host.trimmingCharacters(in: .whitespaces).lowercased()
        return sites.values.first { $0.descriptor.host.lowercased() == needle }
    }

    func site(for url: URL) -> (any InteractiveSite)? {
        guard let host = url.host else { return nil }
        return site(forHost: host)
    }

    func site(withID id: String) -> (any InteractiveSite)? {
        sites[id]
    }

    var allSites: [any InteractiveSite] {
        Array(sites.values)
    }
}