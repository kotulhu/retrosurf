import Foundation

enum SiteEffect: Sendable, Codable, Equatable {
    case setFlag(String, Bool)
    case addItem(String)
    case advanceQuest(String, String)
    case endGame(String)
    /// Grants points towards the hidden achievement dashboard.
    /// The ONLY effect that moves the numeric "score" — achievement events
    /// are fired from this path, never from plain flag changes.
    case addScore(Int)
    /// Registers a statically-served page (host + persisted HTML) into the
    /// live SiteSession registry immediately — no app restart. The homepage
    /// site (Part 1) fires this the moment the player publishes homepage.su.
    /// Persists the HTML into SiteCatalog's user-added dir and registers a
    /// StaticSite so the page is served by the SAME render path as curated
    /// sites from this very second.
    case registerStaticSite(SiteDescriptor, String)
    /// Opens the native file chooser for an interactive site's local image.
    case selectLocalPhoto(String)
}

enum SiteResponse: Sendable {
    case page(SitePage)
    case redirect(URL)
    case alert(String)
    case effect(SiteEffect)
    case download(SiteDownload)
    case compound([SiteResponse])
    case failure(String)
}

/// A downloadable file offered by an interactive site. The browser simulates
/// the transfer against the live modem speed; no real filesystem write occurs.
struct SiteDownload: Sendable, Hashable, Identifiable {
    let id: String
    let fileName: String          // e.g. "winamp_setup.exe"
    let sizeBytes: Int
    let sourceURL: URL            // where it came from
    let hasVirus: Bool
    let category: String          // "wallpaper" | "program" | "music"
    let description: String
}
