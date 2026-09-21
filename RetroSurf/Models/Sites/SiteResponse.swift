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
}

enum SiteResponse: Sendable {
    case page(SitePage)
    case redirect(URL)
    case alert(String)
    case effect(SiteEffect)
    case compound([SiteResponse])
    case failure(String)
}