import Foundation

struct StaticSiteContent: Codable, Sendable {
    var html: String
}

/// Ready-made static page (e.g. published homepage.su). Registered in the
/// live SiteSession registry without an app restart.
final class StaticSite: BaseInteractiveSite<StaticSiteContent> {
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
        return .page(SitePage(url: url, title: descriptor.displayName, html: state.html))
    }

    private func url(for request: SiteRequest) -> URL? {
        switch request {
        case .open(let u): return u
        default: return URL(string: "http://\(descriptor.host)/")
        }
    }
}
