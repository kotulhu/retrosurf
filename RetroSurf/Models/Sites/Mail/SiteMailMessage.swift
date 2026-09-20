import Foundation

struct SiteMailMessage: Codable, Sendable, Identifiable {
    enum Folder: String, Codable, Sendable {
        case inbox, sent, drafts
    }

    init(id: Int, from: String, to: String, subject: String, bodyHTML: String, timestamp: Date, isRead: Bool, folder: Folder, tag: String?) {
        self.id = id
        self.from = from
        self.to = to
        self.subject = subject
        self.bodyHTML = bodyHTML
        self.timestamp = timestamp
        self.isRead = isRead
        self.folder = folder
        self.tag = tag
    }

    let id: Int
    let from: String
    let to: String
    let subject: String
    let bodyHTML: String
    let timestamp: Date
    var isRead: Bool
    var folder: Folder
    /// Opaque tag. When the message is read for the first time,
    /// MailSite emits `.setFlag("mail.read.\(tag)", true)`.
    var tag: String?
}