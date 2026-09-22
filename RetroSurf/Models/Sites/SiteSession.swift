import Combine
import Foundation

@MainActor
final class SiteSession: ObservableObject {
    /// UserDefaults key holding [String: Data] snapshots of every registered site.
    static let snapshotsDefaultsKey = "InteractiveSites.snapshots"

    let registry: SiteRegistry

    init(registry: SiteRegistry) {
        self.registry = registry
    }

    /// Route a request to the right site and return its response.
    /// Unknown host -> .failure("Host not found")
    func dispatch(_ request: SiteRequest) async -> SiteResponse {
        switch request {
        case .open(let url), .submit(let url, _):
            guard let host = url.host else {
                return .failure("Host not found: \(url.absoluteString)")
            }
            guard let site = registry.site(forHost: host) else {
                return .failure("Host not found: \(host)")
            }
            return await site.handle(request)

        case .invoke(let action, let payload):
            // Action arrived as "host:action" — split on the first colon.
            guard let colon = action.firstIndex(of: ":") else {
                return .failure("Host not found: \(action)")
            }
            let host = String(action[..<colon]).trimmingCharacters(in: .whitespaces)
            let strippedAction = String(action[action.index(after: colon)...])
            guard let site = registry.site(forHost: host) else {
                return .failure("Host not found: \(host)")
            }
            return await site.handle(.invoke(action: strippedAction, payload: payload))
        }
    }

    /// Persist all site states into a dictionary keyed by descriptor.id.
    /// GameProgress is the intended persistence host; snapshots are handed
    /// to its save/restore path rather than persisted here.
    func snapshotAll() -> [String: Data] {
        var result: [String: Data] = [:]
        for site in registry.allSites {
            result[site.descriptor.id] = site.snapshot()
        }
        return result
    }

    /// Restore all sites from a snapshot. Skip unknown ids silently,
    /// tolerate missing keys; throw only on a genuinely broken payload.
    func restoreAll(from snapshots: [String: Data]) throws {
        for site in registry.allSites {
            guard let data = snapshots[site.descriptor.id] else { continue }
            try site.restore(from: data)
        }
    }

    /// Debug progress reset: returns every interactive site (pochta.su,
    /// homepage.su…) to its unplayed state and writes fresh empty snapshots so
    /// the old session state does not come back on the next launch or navigation.
    func resetAllGameplay() {
        for site in registry.allSites {
            switch site {
            case let mail as MailSite:
                mail.state = MailState()
            case let home as HomepageSite:
                home.state = HomepageState.defaults
            default:
                site.resetGameplay()
            }
        }
        let snapshots = snapshotAll()
        UserDefaults.standard.set(snapshots, forKey: Self.snapshotsDefaultsKey)
        UserDefaults.standard.synchronize()
    }
}