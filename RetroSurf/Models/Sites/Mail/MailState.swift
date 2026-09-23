import Foundation

/// Transient state of the compose form, kept between attach/remove round-trips
/// so the player's text and selected files survive navigation.
struct ComposeDraft: Codable, Sendable {
    var to: String = ""
    var subject: String = ""
    var body: String = ""
    var attachments: [MailAttachment] = []
}

struct MailState: Codable, Sendable {
    var account: MailAccount?
    var session: MailSession?
    var messages: [SiteMailMessage] = []
    var nextMessageId: Int = 1
    var composeDraft: ComposeDraft = ComposeDraft()

    enum CodingKeys: String, CodingKey {
        case account, session, messages, nextMessageId, composeDraft
    }

    init(account: MailAccount? = nil, session: MailSession? = nil, messages: [SiteMailMessage] = [], nextMessageId: Int = 1, composeDraft: ComposeDraft = ComposeDraft()) {
        self.account = account
        self.session = session
        self.messages = messages
        self.nextMessageId = nextMessageId
        self.composeDraft = composeDraft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decodeIfPresent(MailAccount.self, forKey: .account)
        session = try c.decodeIfPresent(MailSession.self, forKey: .session)
        messages = try c.decodeIfPresent([SiteMailMessage].self, forKey: .messages) ?? []
        nextMessageId = try c.decodeIfPresent(Int.self, forKey: .nextMessageId) ?? messages.count + 1
        composeDraft = try c.decodeIfPresent(ComposeDraft.self, forKey: .composeDraft) ?? ComposeDraft()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(account, forKey: .account)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encode(messages, forKey: .messages)
        try c.encode(nextMessageId, forKey: .nextMessageId)
        try c.encode(composeDraft, forKey: .composeDraft)
    }
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