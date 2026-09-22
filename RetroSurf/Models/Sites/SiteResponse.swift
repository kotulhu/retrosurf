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
    case compound([SiteResponse])
    case failure(String)
}
