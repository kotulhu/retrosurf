import Foundation

struct HomepageState: Codable, Sendable {
    var isPublished = false
    var background: String = "stars"
    var textColor: String = "#000000"
    var aboutMeText: String = ""
    var photoURL: String?
    var photoFilename: String?
    var isShared = false
    var invitedFriends: [String] = []
    var account: HomepageAccount?
    var session: HomepageSession?
    var feedbackCount = 0

    static let defaults = HomepageState()
    static let backgroundOptions: [[String: String]] = [
        ["id": "stars", "name": "Звёздное небо"],
        ["id": "clouds", "name": "Облака"],
        ["id": "construction", "name": "Страница в разработке"]
    ]
}

struct HomepageAccount: Codable, Sendable {
    let login: String
    let password: String
    let email: String
    let createdAt: Date
}

struct HomepageSession: Codable, Sendable {
    let login: String
    let loggedInAt: Date
}
