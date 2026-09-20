import Foundation

enum SiteEffect: Sendable, Codable, Equatable {
    case setFlag(String, Bool)
    case addItem(String)
    case advanceQuest(String, String)
    case endGame(String)
}

enum SiteResponse: Sendable {
    case page(SitePage)
    case redirect(URL)
    case alert(String)
    case effect(SiteEffect)
    case compound([SiteResponse])
    case failure(String)
}