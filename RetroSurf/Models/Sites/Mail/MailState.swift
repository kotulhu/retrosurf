import Foundation

struct MailState: Codable, Sendable {
    var account: MailAccount?
    var session: MailSession?
    var messages: [SiteMailMessage] = []
    var nextMessageId: Int = 1
}

struct MailAccount: Codable, Sendable {
    let username: String
    let password: String
    let displayName: String
    let secretQuestion: String
    let secretAnswer: String
    let createdAt: Date
}

struct MailSession: Codable, Sendable {
    let username: String
    let loggedInAt: Date
}