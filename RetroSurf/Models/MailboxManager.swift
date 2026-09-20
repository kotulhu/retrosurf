import Combine
import Foundation

enum MailCategory: String, Codable {
    case registrationConfirmation
    case spam
    case newsletter
    case questAnnouncement
}

struct MailMessage: Codable, Identifiable {
    let id: String
    let from: String
    let subject: String
    let body: String
    let date: Date
    var isRead: Bool
    let relatedSiteID: String?
    let category: MailCategory
}

@MainActor
final class MailboxManager: ObservableObject {
    @Published private(set) var messages: [MailMessage] = []

    private enum Keys {
        static let mailbox = "MailboxManager.messages"
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Keys.mailbox),
              let decoded = try? JSONDecoder().decode([MailMessage].self, from: data) else {
            return
        }
        messages = decoded
    }

    func deliver(_ message: MailMessage) {
        messages.insert(message, at: 0)
        persist()
    }

    func markRead(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              !messages[index].isRead else { return }
        messages[index].isRead = true
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: Keys.mailbox)
        }
        UserDefaults.standard.synchronize()
    }
}