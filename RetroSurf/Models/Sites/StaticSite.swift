import Foundation

struct StaticSiteContent: Codable, Sendable {
    var html: String
}

/// Ready-made static page (e.g. published homepage.su). Registered in the
/// live SiteSession registry without an app restart.
final class StaticSite: BaseInteractiveSite<StaticSiteContent> {
    private var extraPages: [String: String] = [:]

    init(host: String, displayName: String, html: String) {
        super.init(
            descriptor: SiteDescriptor(
                id: host, host: host, displayName: displayName,
                iconSystemName: "house"
            ),
            initialState: StaticSiteContent(html: html)
        )
    }

    override func handle(_ request: SiteRequest) async -> SiteResponse {
        guard let url = url(for: request) else { return .failure("Host not found") }
        let path = url.path.isEmpty ? "/" : url.path
        if let runtimeHTML = extraPages[path] {
            return .page(SitePage(url: url, title: descriptor.displayName, html: runtimeHTML))
        }
        return .page(SitePage(url: url, title: descriptor.displayName, html: state.html))
    }

    /// Adds (or replaces) a runtime page served under the given path on this host.
    /// The path is normalized to start with "/" and end without a trailing slash.
    /// Runtime pages are not persisted across relaunches.
    func addPage(path: String, html: String) {
        extraPages[Self.normalizedPath(path)] = html
    }

    static func normalizedPath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.hasPrefix("/") { value = "/" + value }
        while value.hasSuffix("/"), value.count > 1 { value.removeLast() }
        return value
    }

    private func url(for request: SiteRequest) -> URL? {
        switch request {
        case .open(let u): return u
        default: return URL(string: "http://\(descriptor.host)/")
        }
    }
}
